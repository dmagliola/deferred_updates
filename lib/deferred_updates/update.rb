module DeferredUpdates
  # Defer updates of fields
  #
  # Internals:
  #   Deferring: Store the value in a hash, and the ID in a ZSet (score is Time.now, to update least frequently updated records first).
  #                I need this because I can't read "N" fields off of a hash, it's specific-ones or all.
  #                I'd like to do this with a Set instead of a ZSet, but I can't use SPOP in LUA scripts :-(
  #  Processing: Gets N IDs from the ZSet, removes them, gets the values from the Hash, and removes them from the Hash, with a LUA script.
  #                Updates by multi-INSERTing into a temp table then updating with a JOIN to the temp table.
  module Update
    def self.defer(model_instance, field, value, options = {})
      DeferredUpdates.with_redis_connection(options[:redis]) do |redis|
        redis.pipelined do |predis|
          predis.hset redis_key(model_instance.class, field, "values"), model_instance.id, value
          predis.zadd redis_key(model_instance.class, field, "ids"), Time.now.to_f, model_instance.id
        end
      end
    end

    # This will update the field with the value in the Hash score.
    def self.process(klass, field, options = {})
      options = { batch_size: DeferredUpdates.configuration.default_update_batch_size,
                  max_running_time: DeferredUpdates.configuration.queue_processing_max_running_time }.
                  merge(options)

      field_type = klass.columns_hash[field].type
      temp_table = TemporaryTable.for_type(field_type)
      temp_table.create_table

      ids_key = self.redis_key(klass, field, "ids")
      values_key = self.redis_key(klass, field, "values")

      DeferredUpdates.with_redis_connection(options[:redis]) do |redis|
        LoopHard.loop(timeout: options[:max_running_time]) do
          # TODO: Make this more reliable to random crashes.
          get_rows_script = 'local ids = redis.call("ZRANGEBYSCORE", KEYS[1], "-inf", "+inf", "LIMIT", 0, ARGV[1])
                             if ids ~= false and #ids ~= 0 then
                               redis.call("ZREM", KEYS[1], unpack(ids))
                               local hash_data = redis.call("HMGET", KEYS[2], unpack(ids))
                               redis.call("HDEL", KEYS[2], unpack(ids))
                               return {ids, hash_data}
                             end
                             return nil'
          rows = redis.eval(get_rows_script, [ids_key, values_key], [options[:batch_size]])
          rows = rows[0].zip(rows[1]) unless rows.blank? # Script returns an array with 2 arrays, one with IDs, one with Values. Zip them.
          break if rows.blank? || rows.empty?

          temp_table.process_updates(klass.table_name, field, rows)
        end
      end

      temp_table.drop_table
    end

    private

    # data type can be "values" (for the hash) or "ids" (for the set)
    def self.redis_key(klass, field, data_type)
      "#{DeferredUpdates.configuration.redis_namespace}deferred:update:#{klass.to_s.underscore}_#{field}"
    end
  end
end

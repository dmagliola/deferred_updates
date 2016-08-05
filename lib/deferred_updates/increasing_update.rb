module DeferredUpdates
  # Defer updates of fields that are floats or can be cast to floats, that only increase
  #
  # Internals:
  #   Deferring: Adds the record ID and the numeric value to a ZSet, using the value as the score.
  #   Processing: Gets the first N records with ZRANGEBYSCORE.
  #               Updates by multi-INSERTing into a temp table then updating with a JOIN to the temp table.
  #               Removes from ZSet using ZREMRANGEBYSCORE, with the maximum found score as the threshold.
  module IncreasingUpdate
    # This only works for floats that monotonically increase over time,
    #   because of how we get the first few from the ZSET by score, and
    #   also remove by score. If scores are not constantly increasing, you
    #   may lose an update due to concurrency
    def self.defer(model_instance, field, value, options = {})
      DeferredUpdates.with_redis_connection(options[:redis]) do |redis|
        redis.zadd redis_key(model_instance.class, field), value, model_instance.id
      end
    end

    # This will update the field with the value in the ZSet score.
    # If it needs to be processed somehow (for example, to turn it back into a timestamp with Time.at)
    #   call this method with a block, which will be called with the array of rows, to map them back
    #   into what they need to be mapped
    # Explain what max_score is! (to not update things that got very recently updated, if using dates)
    def self.process(klass, field, options = {})
      options = { max_score: "+inf",
                  batch_size: DeferredUpdates.configuration.default_update_batch_size,
                  max_running_time: DeferredUpdates.configuration.queue_processing_max_running_time }.
                  merge(options)

      field_type = klass.columns_hash[field].type
      temp_table = TemporaryTable.for_type(field_type)
      temp_table.create_table

      key = redis_key(klass, field)

      DeferredUpdates.with_redis_connection(options[:redis]) do |redis|
        LoopHard.loop(timeout: options[:max_running_time]) do
          rows = redis.zrangebyscore(key, "-inf", options[:max_score],
                                     limit: [0, options[:batch_size]],
                                     with_scores: true)
          break if rows.empty?
          max_found_score = rows.last[1]

          # Rows are [model_id, score]
          rows = yield(rows) if block_given?

          temp_table.process_updates(klass.table_name, field, rows)

          redis.zremrangebyscore(key, "-inf", max_found_score)
        end
      end

      temp_table.drop_table
    end

    private

    def self.redis_key(klass, field)
      "#{DeferredUpdates.configuration.redis_namespace}deferred:update:#{klass.to_s.underscore}_#{field}"
    end
  end
end

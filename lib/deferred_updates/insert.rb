module DeferredUpdates
  # Defer record INSERTing until later
  #
  # Internals:
  #   Deferring: Adds a Hash of attributes (in JSON) to a Redis List.
  #   Processing: Reads the list in batches with LRANGE/LTRIM and does one multi-INSERT per batch.
  module Insert
    def self.defer(model_instance, options = {})
      DeferredUpdates.with_redis_connection(options[:redis]) do |redis|
        redis.rpush(redis_key(model_instance.class), model_instance.attributes.to_json)
      end
    end

    def self.process(klass, options = {})
      options = { batch_size: DeferredUpdates.configuration.default_insert_batch_size,
                  max_running_time: DeferredUpdates.configuration.queue_processing_max_running_time }.
                merge(options)

      key = self.redis_key(klass)
      DeferredUpdates.with_redis_connection(options[:redis]) do |redis|
        LoopHard.loop(timeout: options[:max_running_time]) do
          rows = redis.pipelined do |predis|
            predis.multi do |mredis|
              # TODO: Make this more resilient by doing a RPUSH of the things I'm "popping" here into a second key, unique to this "loop", with a LUA script
              #    and then empty that key when the loop is done. That way, if the process crashes mid-loop, we don't lose those inserts. Basically, a RPOPLPUSH
              #    that works on multiple records at once
              #    something would have to discover and recycle those unique keys to recover those lost records
              #    also, how do I ensure that I don't get the opposite. That is, I do write to DB, but crash before removing that key, and then get duplicates?
              #    rpoplpush works under the assumption that Sidekiq jobs are idempotent....
              mredis.lrange(key, 0, options[:batch_size] - 1) # Get the first 100
              mredis.ltrim(key, options[:batch_size], -1) # Trim to positions "101 to end"
            end
          end
          rows = rows[0] # The multi gives me the reply to "lrange" and to "ltrim". I want the first one only
          break if rows.empty?

          rows = rows.map{|row| JSON.parse(row)}

          # Send the rows back to the caller, if the caller wants to do something interesting with them
          yield(rows) if block_given?

          # Convert rows from hashes into positional arrays to call Import without instantiating models
          fields = rows[0].keys
          rows = rows.map do |row|
            fields.map {|field| row[field] }
          end

          klass.import(fields, rows, validate: false, timestamps: false)
        end
      end
    end

    private

    def self.redis_key(klass)
      "#{DeferredUpdates.configuration.redis_namespace}deferred:insert:#{klass.to_s.underscore}"
    end
  end
end

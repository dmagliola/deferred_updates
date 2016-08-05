module DeferredUpdates
  # Gets a connection to Redis using whatever method was configured,
  # and yields it to the block passed in.
  # If a connection is passed in as a parameter, use that one instead of global configuration.
  # @return [Object] Whatever your block returned
  def self.with_redis_connection(redis = nil)
    conf = DeferredUpdates.configuration

    if redis
      yield(redis)
    elsif conf.redis_connection_pool.present?
      conf.redis_connection_pool.with do |redis|
        yield(redis)
      end
    elsif conf.redis_connection.present?
      yield(conf.redis_connection)
    elsif conf.redis_connection_proc.present? || conf.redis_connection_settings.present?
      conn = conf.redis_connection_proc.present? ?
                conf.redis_connection_proc.call :
                Redis.new(conf.redis_connection_settings)
      result = yield(conn)
      conn.disconnect! if conn.respond_to?(:disconnect!)
      result
    end
  end
end

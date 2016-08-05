require_relative "test_helper"

class ConnectionTest < MiniTest::Test
  context "with resetting of configuration" do
    setup do
      TestResetHelper.reset_configuration
    end

    teardown do
      TestResetHelper.reset_configuration
    end

    should "use the object passed in, if there is one" do
      redis_conn = Object.new

      DeferredUpdates.with_redis_connection(redis_conn) do |redis|
        assert_equal redis_conn.object_id, redis.object_id
      end
    end

    should "connect using a connection pool" do
      redis_pool = ::ConnectionPool.new(size: 2, timeout: 2) do
        Redis.new($RedisConnectionSettings)
      end

      DeferredUpdates.configure do |config|
        config.redis_connection_pool = redis_pool
        config.redis_connection_settings = {host: 'localhost', port: 1111} # Just to make sure it's not using this
      end

      test_connection
    end

    should "connect using a connection proc" do
      DeferredUpdates.configure do |config|
        config.redis_connection_proc = Proc.new{ Redis.new($RedisConnectionSettings) }
        config.redis_connection_settings = {host: 'localhost', port: 1111} # Just to make sure it's not using this
      end

      test_connection
    end

    should "connect using an existing connection" do
      conn = Redis.new($RedisConnectionSettings)

      DeferredUpdates.configure do |config|
        config.redis_connection = conn
        config.redis_connection_settings = {host: 'localhost', port: 1111} # Just to make sure it's not using this
      end

      test_connection
    end

    should "connect using default connection settings" do
      DeferredUpdates.configure do |config|
        config.redis_connection_settings = {host: 'localhost', port: 6379}
      end

      test_connection
    end
  end

  private

  def test_connection
    DeferredUpdates.with_redis_connection do |redis|
      redis.set "aaa", "bbb"
      assert_equal "bbb", redis.get("aaa")
    end
  end
end

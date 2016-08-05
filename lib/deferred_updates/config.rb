module DeferredUpdates

  # Thrown when a config setting is invalid
  class InvalidConfigSettingError < StandardError; end

  # Returns the current configuration
  def self.configuration
    @configuration ||=  Configuration.new
  end

  # Yields the current configuration, allowing the caller to modify it in a block
  def self.configure
    yield(configuration) if block_given?
  end

  # Holds the configuration
  class Configuration
    # Connection Pool used to get a new Redis connection. It's heavily recommended to set this.
    # One of :redis_connection_pool, :redis_connection_proc, :redis_connection_settings or :redis_connection must be set
    attr_accessor :redis_connection_pool

    # Proc that yields a connection object when needed
    # One of :redis_connection_pool, :redis_connection_proc, :redis_connection_settings or :redis_connection must be set
    attr_accessor :redis_connection_proc

    # Hash specifying the settings to connect to Redis. Gets passed to `Redis.new`
    # One of :redis_connection_pool, :redis_connection_proc, :redis_connection_settings or :redis_connection must be set
    # Defaults to localhost:6379
    attr_accessor :redis_connection_settings

    # Already established connection to Redis for the library to use
    # One of :redis_connection_pool, :redis_connection_proc, :redis_connection_settings or :redis_connection must be set
    attr_accessor :redis_connection

    # String prefix to use for all keys.
    # Defaults to ''. All keys will also start with 'deferred:' in addition to this prefix,
    attr_accessor :redis_namespace

    # Maximum time to run queue processing for. Defaults to 9.5 minutes.
    # Set this to at least 10 seconds less than the frequency of running your cron job.
    attr_accessor :queue_processing_max_running_time

    # Batch size for INSERTs. Defaults to 100
    attr_accessor :default_insert_batch_size

    # Batch size for UPDATEs. Defaults to 1000
    attr_accessor :default_update_batch_size

    def initialize
      @redis_connection_settings = {host: 'localhost', port: 6379}
      @redis_namespace = ""
      @queue_processing_max_running_time = 60 * 9.5
      @default_insert_batch_size = 100
      @default_update_batch_size = 1000
    end
  end
end
require "rubygems"

require "simplecov"
require "coveralls"
SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter[
    SimpleCov::Formatter::HTMLFormatter,
    Coveralls::SimpleCov::Formatter
]
SimpleCov.start do
  add_filter "/test/"
  add_filter "/gemfiles/vendor"
end

require "codeclimate-test-reporter"
CodeClimate::TestReporter.start

require "minitest/autorun"
require "minitest/reporters"
MiniTest::Reporters.use!

require "shoulda"
require "shoulda-context"
require "shoulda-matchers"
require "mocha/setup"

# Make the code to be tested easy to load.
$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), "..", "lib"))

require 'active_support/testing/assertions'
include ActiveSupport::Testing::Assertions

require "benchmark"

require "redis"
require "connection_pool"
require "deferred_updates"

# Add helper methods to use in the tests
$RedisConnectionSettings = {host: 'localhost', port: 6379, db: 2}

class TestResetHelper
  def self.reset_configuration
    DeferredUpdates.instance_variable_set(:@configuration, DeferredUpdates::Configuration.new)
    DeferredUpdates.configure do |config|
      config.redis_connection_settings = $RedisConnectionSettings
    end
  end
end

TestResetHelper.reset_configuration


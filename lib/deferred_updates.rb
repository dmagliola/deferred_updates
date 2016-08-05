require 'deferred_updates/config'
require 'deferred_updates/redis_connection'
require 'deferred_updates/version'

# Defer low-priority database INSERTs and UPDATEs to a later time, to reduce contention
module DeferredUpdates
end
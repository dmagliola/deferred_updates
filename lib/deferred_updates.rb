require 'deferred_updates/config'
require 'deferred_updates/redis_connection'

require 'deferred_updates/temporary_table'

require 'deferred_updates/insert'
require 'deferred_updates/increasing_update'
require 'deferred_updates/increasing_datetime_update'
require 'deferred_updates/update'

require 'deferred_updates/version'

# Defer low-priority database INSERTs and UPDATEs to a later time, to reduce load and contention,
#   and improve performance
module DeferredUpdates
end
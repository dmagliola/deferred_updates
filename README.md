# deferred_updates

[![Build Status](https://travis-ci.org/dmagliola/deferred_updates.svg?branch=master)](https://travis-ci.org/dmagliola/deferred_updates)
[![Coverage Status](https://coveralls.io/repos/dmagliola/deferred_updates/badge.svg?branch=master&service=github)](https://coveralls.io/github/dmagliola/deferred_updates?branch=master)
[![Code Climate](https://codeclimate.com/github/dmagliola/deferred_updates/badges/gpa.svg)](https://codeclimate.com/github/dmagliola/deferred_updates)
[![Inline docs](http://inch-ci.org/github/dmagliola/deferred_updates.svg?branch=master&style=flat)](http://inch-ci.org/github/dmagliola/deferred_updates)
[![Gem Version](https://badge.fury.io/rb/deferred_updates.png)](http://badge.fury.io/rb/deferred_updates)

Queue up database INSERTs and UPDATEs that don't need to happen immediately, and run them in batches later.

Running database updates in large batches is much more efficient than running them one by one,
reducing total time running the updates, load on the database server, and contention due to locking of those rows.

In the project that spawned this gem, slow-drip DB updates were the biggest bottleneck by far, and
replacing this with this mechanism kept the DB relaxed for a long, long time.

`deferred_updates` uses Redis to store the queues. Make sure you point it to a Redis instance configured
to persist data to disk.

## Typical use cases:
- Batch up inserts to a database to tables that won't be read immediately. Logs, statistics, audits, etc.
- Batch up updates to fields that change frequently but that don't need to be up to date.
- Especially fields like "last_seen_at", "last_request_at", etc. These tend to get updated very often,
    in many cases in every request, read infrequently, and their freshness is generally not critical.

Updates are the most expensive operation for a RDBMS, so the more you can defer, the more load you will save.

## Download

Gem:

`gem install deferred_updates`

## Installation

Load the gem in your GemFile.

  `gem "deferred_updates"`

## Usage:

For each ActiveRecord Model (for inserts), or Model / Field combination (for updates) whose update
you'd like to defer, you need to do two things:

- Call `defer` on the appropriate class in the `DeferredUpdates` module (see types of operations below)
- Every now and then, call `process` on the same class specifying the Model, or Model/Field, to actually
  process the queued up operations

## Type of operations that can be deferred:

- Inserts: Simply call `Insert.defer` instead of `Model.create`
- Increasing Numeric Field Updates: Used for updates to a field that can be represented as a float, and which ONLY increases.
  - Can't be use for things that cannot be mapped to a float.
  - Can't be used for values that can go DOWN over time.
  - Ideal for counters
  - Call `IncreasingUpdate.defer` instead of updating your model
- Increasing Datetime Field Updates: Just an adapter on top of IncreasingUpdate that maps datetimes to/from floats.
  - Call `IncreasingDatetimeUpdate.defer` instead of updating your model
- Other Updates: Updates to fields of any other type
  - Prefer the Increasing Updates if possible, as they are simpler and more performant.
  - But for every other type of field (castable to a String): call `Update.defer` instead of updating your model

All the `defer` methods optionally accept a `redis` parameter to specify the connection to use.
Useful if you are doing these updates inside a Redis pipeline, to save roundtrips to Redis.

Also mandatory if you havent't configured a Redis connection pool in the Gem's configuration.

## Periodically processing the queued up updates / inserts

Every few minutes, from your cron script or a sidekiq worker, call the corresponding one of these
for each thing you are deferring:

- DeferredUpdates::Insert.process(Model)
- DeferredUpdates::IncreasingUpdate.process(Model, :field)
- DeferredUpdates::IncreasingDatetimeUpdate.process(Model, :field)
- DeferredUpdates::Update.process(Model, :field)

All `process` methods accept these extra, optional parameters:
- **redis**: The redis connection to use. **DO NOT** pass a connection that has had a pipeline,
    or a `MULTI`transaction started!
- **batch_size**: How many records to INSERT / UPDATE at once on each batch.
- **max_running_time** = Maximum time to run before exiting gracefully even if there are more batches to process.

More information about both of these in the next section.


## Configuration

```
DeferredUpdates.configure do |config|
  config.redis_connection_pool = $RedisPool
  config.redis_connection = $Redis
  config.redis_connection_proc = Proc.new{ Redis.new(connection_settings) }
  config.redis_connection_settings = {host: 'localhost', port: 6379}
  config.redis_namespace = "defer"
  config.queue_processing_max_running_time = 570 # 9.5 minutes
  config.default_insert_batch_size = 100
  config.default_update_batch_size = 1000
end
```

The configuration specifies:

- **redis_connection_pool:** The Redis connection pool to get Redis connections from. This is
    the recommended configuration.
    You can use any of the other configuration options, however, or you can also pass in a Redis
    connection to all the methods that deal with Redis.

- **redis_connection:** Please don't use a single Redis connection for your whole app, use a connection pool instead.
    But if that's not a choice, you can set that connection here.
    This is also optional, you can pass in a Redis connection to the methods that deal with Redis.
    Do not set both `redis_connection_pool` and `redis_connection`.

- **redis_connection_proc:** If you would like `deferred_updates` to connect to Redis every time
    it needs to, you can pass in a `Proc` that will get called every time a connection is needed,
    and which returns a connected Redis instance.

- **redis_connection_settings:** Alternatively, you can configure the connection settings, and
    `deferred_updates` will connect to Redis every time it needs to. Finally, if you have a default
    Redis running in localhost in the default port, you don't need to set anything,
    `deferred_updates` will connect to it automatically.

- **redis_namespace:** Prefix to add to all the Redis keys. Defaults to "", but all keys start with
    "deferred:" anyway.

- **queue_processing_max_running_time:** When processing the queue, run for at most these many seconds.
    The queue processing will finish after (approximately) that time, or once the queue is empty.
    Generally, the queue will be emptied, this is just a failsafe in case the queue has grown huge.
    Set this to a bit less than the frequency with which you run your cron script, so you don't get
    overlaps.
    Note that this is not a *hard* timeout. This time will be checked between each batch of records
    updated, so give it some leeway.
    The default value is 9.5 minutes, which assumes the cron script will run every 10 minutes.
    This can be overridden at calls to `process`

- **default_insert_batch_size** and **default_insert_batch_size**: How many records to INSERT / UPDATE
    at once when processing the queue, by default. Defaults to 100 and 1000 respectively.
    This can be overridden at calls to `process`


## Exiting gracefully from long-running calls to `process`

When processing the queue of pending updates, `deferred_updates` does the following:

- Loop:
  - Get the next batch of records to INSERT / UPDATE from Redis
  - INSERT / UPDATE them in the database
  - Exit if it's been running for more than `max_running_time`
  - Exit if the process needs to shut down
  - Exit if there are no more batches to run

The logic behind exiting if `max_running_time` has expired is to avoid overlapping runs of the same
table / field. If your cron runs every 10 minutes, you want to exit comfortably before that, since this
is not a hard timeout; the batch that's running when the time expired will continue to run, we just
won't pick up a new one after that one is done. So give it some leeway.

The other condition to exit before finishing all batches is if the process is supposed to shut down.
You want to exit gracefully as soon as you finish this batch, rather than be killed mercilessly mid-batch.

`deferred_updates` uses the [loop_hard](https://github.com/dmagliola/loop_hard) gem for this.

- If you are calling `process` from inside a Sidekiq job, there is nothing for you to worry about.
    `loop_hard` will automatically detect if Sidekiq is shutting down and stop for you.
- If you are calling `process` in a simple cron script, or a situation where you're not handling
    signals manually, call `LoopHard::SignalTrap.trap_signals` at some point in before calling `process`
- If you are already handling your own signals, then in your capture block, whenever you decide that
    `process` should stop, call `LoopHard::SignalTrap.signal_trapped`

Read more about this in the [loop_hard docs](https://github.com/dmagliola/loop_hard)

## Version Compatibility and Continuous Integration

Tested with [Travis](https://travis-ci.org/dmagliola/deferred_updates) using Ruby 1.9.3, 2.1.7, 2.2.4 and 2.3.1.

To locally run tests do:

```
rake test
```

## Copyright

Copyright (c) 2016, Daniel Magliola

See LICENSE for details.


## Users

This gem is being used by:

- [MSTY](https://www.msty.com)
- You? please, let us know if you are using this gem.


## Changelog

### Version 0.1.0 (Oct 20th, 2015)
- Newly released gem

## Contributing

1. Fork it
1. Create your feature branch (`git checkout -b my-new-feature`)
1. Code your thing
1. Write and run tests:
        bundle install
        rake test
1. Write documentation and make sure it looks good: yard server --reload
1. Add items to the changelog, in README.
1. Commit your changes (`git commit -am "Add some feature"`)
1. Push to the branch (`git push origin my-new-feature`)
1. Create new Pull Request


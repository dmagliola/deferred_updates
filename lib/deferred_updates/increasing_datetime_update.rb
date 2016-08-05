module DeferredUpdates
  # Defer updates of fields that are datetimes, that only increase
  #
  # Internals: Uses IncreasingUpdate, but provides mapping to and from float for datetimes
  module IncreasingDateTimeUpdate
    # This only works for datetimes that monotonically increase over time,
    #   because of how we get the first few from the ZSET by score, and
    #   also remove by score. If scores are not constantly increasing, you
    #   may lose an update due to concurrency
    def self.defer(model_instance, field, value, options = {})
      IncreasingUpdate.defer(model_instance, field, value.to_f, options)
    end

    # This will update the field with the value in the ZSet score.
    # If it needs to be processed somehow (for example, to turn it back into a timestamp with Time.at)
    #   call this method with a block, which will be called with the array of rows, to map them back
    #   into what they need to be mapped
    # Explain what max_score is! (to not update things that got very recently updated, if using dates)
    def self.process(klass, field, options = {})
      IncreasingUpdate.defer(klass, field, options) do |rows|
        rows.map{|row| [row[0], Time.at(row[1])]}
        yield(rows) if block_given? # TODO: Does this work, nested like this? Or do I need to capture &block?
      end
    end
  end
end

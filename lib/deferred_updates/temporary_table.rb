module DeferredUpdates
  # Handling of Temporary Tables:
  # We are using Temporary Tables to do one multi-INSERT operation, and then an UPDATE FROM,
  #   to be able to do the "multi-UPDATE". Now, because we are using the ActiveRecord-Import gem
  #   for the multi-INSERT (we don't really want to do what that one manually), we need to have a
  #   model pointing to that Temporary Table. Surprisingly, having the model with no actual table
  #   in the DB, and creating it and dropping it on demand work. However, once you use it once,
  #   Rails caches the columns and types of the table. When you later need a different data type
  #   for the value column, stuff blows up.
  #
  #   We could use reset_column_information for this, but it looks a bit too global, and I'm not
  #     sure how thread-safe that would be, so I'd rather not. So, to solve this, we need multiple
  #     models, one for each data type we want to be able to multi-UPDATE. The code for all those
  #     is exactly the same, though, so we have the "TemporaryTable" module with all the useful
  #     code, and then 4 models that include it.
  #
  #   TemporaryTable also has `for_type`, to return the appropriate Model for the data type required,
  #     after which all code can just treat them interchangeably.
  module TemporaryTable
    extend ActiveSupport::Concern

    def self.for_type(value_field_type)
      case value_field_type.to_sym
        when :string
          TemporaryTableString
        when :datetime
          TemporaryTableDateTime
        when :integer
          TemporaryTableInteger
        else
          raise "Unsupported column type. Add the TemporaryTable subclass"
      end
    end

    module ClassMethods
      def create_table
        self.drop_table # Just in case
        self.connection.execute("CREATE TEMPORARY TABLE #{self.table_name} (
            id    integer,
            value #{self.connection.type_to_sql(self.value_field_type)}
          )
          ON COMMIT DELETE ROWS")
      end

      # Rows is an array of 2-entry arrays, containing [id, value_to_update]
      # Inserts the rows into the temporary table, and updates the target table with the values
      def process_updates(table_name, field, rows)
        ActiveRecord::Base.transaction do
          mass_import(rows)
          mass_update(table_name, field)
        end
      end

      def drop_table
        self.connection.execute("DROP TABLE IF EXISTS #{self.table_name}")
      end

      # Receives array of [id, value] arrays
      def mass_import(rows)
        self.import([:id, :value], rows, validate: false, timestamps: false)
      end

      def mass_update(target_table, target_column)
        self.connection.execute("UPDATE #{target_table.to_s}
                                    SET #{target_column.to_s} = #{self.table_name}.value
                                    FROM #{self.table_name}
                                    WHERE #{target_table.to_s}.id = #{self.table_name}.id")
      end
    end
  end

  class TemporaryTableString < ActiveRecord::Base
    self.table_name = "temp_deferred_updates_string"
    include TemporaryTable
    def self.value_field_type
      :string
    end
  end

  class TemporaryTableDateTime < ActiveRecord::Base
    self.table_name = "temp_deferred_updates_datetime"
    include TemporaryTable
    def self.value_field_type
      :datetime
    end
  end

  class TemporaryTableInteger < ActiveRecord::Base
    self.table_name = "temp_deferred_updates_integer"
    include TemporaryTable
    def self.value_field_type
      :integer
    end
  end
end

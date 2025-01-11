# frozen_string_literal: true

# Transient Record helps define transient tables and Active Record models.
#
# It's essential to understand Transient Record Contexts in order to use the
# library effectively. Let's start the discussion with how Active Record handles
# connections.
#
# Active Record organizes connection pools around classes. Connecting to
# multiple databases requires defining multiple abstract classes. For example:
#
#     class ApplicationRecord < ActiveRecord::Base
#     end
#
#     class AnalyticsRecord < ApplicationRecord
#       self.abstract_class = true
#
#       connects_to database: { writing: :analytics }
#     end
#
# In this case, +ApplicationRecord.connection+ returns a connection to the
# primary database and +AnalyticsRecord.connection+ returns a connection to the
# other database.
#
# A context is related to an Active Record base class that's used to access the
# database directly and to define transient models. After defining an Active
# Record base class, a context can be created by calling {.context_for} and
# **must** be assigned to a constant.
#
# After the context is created, you can create tables and models by calling
# {Context#create_table} and {Context#define_model}. When you're done, call
# {.cleanup} to drop all transient tables and models
#
# @example Creating a table and a model
#   # Define the context for classes using ActiveRecord::Base to connect. It's
#   # a constant defined outside of the test suite.
#   Primary = TransientRecord.context_for ActiveRecord::Base
#
#   # #create_table is a wrapper around #create_table in Active Record, and
#   # works almost exactly like the that method.
#   Primary.create_table :users do |t|
#     t.string :email, null: false
#   end.define_model do
#     validates :email, presence: true
#   end
#
#   # Instantiate the model
#   user = Primary::User.new email: nil
#
#   # Clean up when done.
#   TransientRecord.cleanup
#
# @example Defining a model for a pre-existing table
#   Primary = TransientRecord.context_for ActiveRecord::Base
#
#   Primary.define_model :User do
#     validates :email, presence: true
#   end
#
#   user = Primary::User.new email: nil
#
# @example Creating a table and a model in another database
#   Analytics = TransientRecord.context_for AnalyticsRecord
#
#   Analytics.create_table :events do |t|
#     # ...
#   end.define_model do
#     # ...
#   end
#
#   event = Analytics::Event.new
#
# @example Executing an arbitrary query
#   # Create a Transient Record context.
#   Primary = TransientRecord.context_for ActiveRecord::Base
#
#   # Call #execute on the context, which is delegated to the same method
#   # provided by Rails.
#   Primary.execute("CREATE ROLE gregnavis")
class TransientRecord
  # Transient Record version number.
  VERSION = "3.0.0"

  # A class representing Transient Record errors.
  class Error < RuntimeError; end

  # A mapping of Active Record base classes to TransientRecord::Contexts.
  @contexts = {}

  class << self
    # Creates a namespace for tables and models corresponding to the given base
    # class.
    #
    # Active Record sets up connection pools for abstract Active Record model
    # classes.
    #
    # @param base_class [Class] class inheriting from {::ActiveRecord::Base}
    # @return [Module] module where transient models will be defined; the module
    #   extends {Context}, so it's instance methods can be called on the module.
    def context_for(base_class)
      @contexts[base_class] ||= Context.create base_class
    end

    def cleanup
      @contexts.each_value(&:cleanup)
      nil
    end
  end

  # A module for creating Transient Record contexts.
  #
  # A context is a Ruby module (created via +Module.new+) and extended with
  # {Context}. This means instance methods below should be called as module
  # methods on a context, **not** as instance methods.
  module Context
    # Creates a context corresponding to the specified base class.
    #
    # @param base_class [Class] Active Record class to use to connect to the
    #   database and as a base class for models.
    #
    # @return [Module] context module used as a namespace for models
    #
    # @api private
    def self.create(base_class)
      Module.new do
        extend Context
        @base_class       = base_class
        @transient_tables = []
      end
    end

    # Creates a transient table.
    #
    # This method can be considered to be a wrapper around +#create_table+ in
    # Active Record, as it forwards its arguments and the block.
    #
    # Transient tables are **not** made temporary in the database (in other
    # words, they are **not** created using +CREATE TEMPORARY TABLE+), because
    # temporary tables are treated differently by Active Record. For example,
    # they aren't listed by +#tables+. If a temporary table is needed then pass
    # +temporary: true+ via options, which Active Record will recognized out of
    # the box.
    #
    # Transient tables must be dropped explicitly by calling {.cleanup} or
    # {#cleanup}.
    #
    # @param table_name [String, Symbol] name of the table to create.
    # @param options [Hash] options to use during table creation; they are
    #   forwarded as is to +create_table+ in Active Record.
    #
    # @yield [table] table definition block forwarded to +create_table+ in
    #   Active Record.
    #
    # @return [ModelDefinitionProxy]
    #
    # @see https://api.rubyonrails.org/classes/ActiveRecord/ConnectionAdapters/SchemaStatements.html#method-i-create_table Documentation for #create_table in Ruby on Rails
    def create_table(table_name, options = {}, &)
      table_name = table_name.to_sym
      @transient_tables << table_name

      @base_class.connection.create_table(table_name, **options, &)

      ModelDefinitionProxy.new self, table_name
    end

    # Defines a transient Active Record model.
    #
    # Calling this method is roughly equivalent to defining a class inheriting
    # from the class the context corresponds to and with class body defined by
    # the block passed to the method.
    #
    # The base class can be customized by passing in a second argument, but it
    # **must** be a subclass of the context's base class.
    #
    # Transient models must be removed explicitly by calling {.cleanup} or
    # {#cleanup}.
    #
    # @example
    #   Primary = TransientRecord.context_for ApplicationRecord
    #
    #   # The following method call ...
    #   Primary.define_model(:User) do
    #     validates :email, presence: true
    #   end
    #
    #   # ... is roughly equivalent to this class definition.
    #   class Primary::User < ApplicationRecord
    #     validates :email, presence: true
    #   end
    #
    #
    # @param model_name [String, Symbol] name of model to define.
    # @param base_class [Class] base class the model should inherit from
    #
    # @yield class definition
    #
    # @return [nil]
    def define_model(model_name, base_class = nil, &)
      base_class ||= @base_class

      if base_class > @base_class
        raise Error.new(<<~ERROR)
          #{model_name} base class is #{base_class.name} but it must be a descendant of #{@base_class.name}
        ERROR
      end

      klass = Class.new base_class
      const_set model_name, klass

      klass.class_eval(&) if block_given?

      nil
    end

    # Executes an arbitrary query.
    #
    # This method is a wrapper around the `#execute` method on the Active Record
    # database connection adapter.
    #
    # @param query [String] query to execute
    # @param name [String] name to log along the query
    # @return The query result returned by the database connection adapter.
    #
    # @see https://api.rubyonrails.org/classes/ActiveRecord/ConnectionAdapters/DatabaseStatements.html#method-i-execute Documentation for #execute in Ruby on Rails
    def execute(query, name = nil)
      @base_class.connection.execute query, name
    end

    # Drops transient tables and models.
    #
    # Calling this method removes all models and drops all tables created within
    # this context. Instead of calling this method, you usually should
    # {.cleanup} to cleanup **all** contexts.
    #
    # Calling this method does the following:
    #
    # 1. Remove all models defined via {#define_model}.
    # 2. Drop all tables created via {#create_table}.
    # 3. Run garbage collection to ensure model classes are truly removed. This
    #    may be needed in some versions of Active Record.
    #
    # @return [nil]
    def cleanup
      constants.each { |name| remove_const name }

      tables_to_remove = @transient_tables
      drop_attempts = tables_to_remove.count * (1 + tables_to_remove.count) / 2

      drop_attempts.times do
        table = tables_to_remove.pop
        break if table.nil?

        begin
          @base_class.connection.drop_table table, force: :cascade, if_exists: true
        rescue ActiveRecord::InvalidForeignKey, ActiveRecord::StatementInvalid
          # ActiveRecord::StatementInvalid is raised by MySQL when attempting to
          # drop a table that has foreign keys referring to it.
          tables_to_remove.unshift(table)
        end
      end

      if !@transient_tables.empty?
        raise Error.new(<<~ERROR)
          The following transient tables could not be removed: #{@transient_tables.join(', ')}.
        ERROR
      end

      GC.start

      nil
    end
  end

  # A model definition proxy is a helper class implementing a fluent
  # interface allowing callers to create a table and its corresponding
  # model in close succession. It's marked private as there's no need for
  # callers to access it directly.
  class ModelDefinitionProxy
    def initialize(context, table_name)
      @context    = context
      @table_name = table_name
    end

    def define_model(...)
      @context.define_model(@table_name.to_s.classify, ...)
    end
  end

  private_constant :ModelDefinitionProxy
end

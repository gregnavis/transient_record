# frozen_string_literal: true

# Transient Record helps define transient tables and Active Record models.
#
# Defining a transient table and model is a two-step process:
#
# 1. {#create_table} to create the table.
# 2. {#define_model} to define the model.
#
# @example Creating a table without a model
#   # #create_table is a wrapper around #create_table in Active Record, and
#   # works almost exactly like the that method.
#   TransientRecord.create_table :users do |t|
#     t.string :email, null: false
#   end
#
# @example Creating a table and a model using fluent interface
#   # The difference between #create_table and its Active Record counterpart is
#   # the return value: Transient Record allows calling #define_model on it.
#   TransientRecord.create_table :users do |t|
#     t.string :email, null: false
#   end.define_model do
#     validates :email, presence: true
#   end
#
#   # The transient model can be referenced via TransientRecord::Models::User.
#   # For example, a new user instance can be instantiated via:
#   user = TransientRecord::Models::User.new email: nil
#
# @example Creating a table and a model with regular interface
#   # Assuming the users table has been created (using Transient Record or
#   # another method), a User model can be defined via:
#   TransientRecord.define_model :User do
#     validates :email, presence: true
#   end
module TransientRecord
  # Transient Record version number.
  VERSION = "1.0.1"

  # A class representing Transient Record errors.
  class Error < RuntimeError; end

  # A module where all temporary models are defined.
  #
  # Models defined via {TransientRecord.define_model}, {TransientRecord#define_model}
  # or {ModelDefinitionProxy#define_model} are put here in order to avoid
  # polluting the top-level namespace, potentially conflicting with identically
  # named constants defined elsewhere.
  #
  # @example
  #   # If a transient users table and its corresponding User model are defined then ...
  #   TransientRecord.create_table :users do |t|
  #     t.string :email, null: false
  #   end.define_model do
  #     validates :email, presence: true
  #   end
  #
  #   # ... the user model can be referenced via:
  #   TransientRecord::Models::User
  module Models
    # Remove all constants from the module.
    #
    # This method is used by {TransientRecord.cleanup} to undefine temporary
    # model classes.
    #
    # @api private
    def self.remove_all_consts
      constants.each { |name| remove_const name }
    end
  end

  def create_table *args, &block
    TransientRecord.create_table(*args, &block)
  end

  def define_model *args, &block
    TransientRecord.define_model(*args, &block)
  end

  # Transient table names are stored in a module instance variable, so that
  # only transient tables can be removed in .cleanup.
  @transient_tables = []

  class << self
    # Create a transient table.
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
    # Transient tables must be dropped explicitly by calling {.cleanup}.
    #
    # @param table_name [String, Symbol] name of the table to create.
    # @param options [Hash] options to use during table creation; they are
    #   forwarded as is to +create_table+ in Active Record.
    #
    # @yield [table] table definition forwarded to +create_table+ in Active
    #   Record.
    #
    # @return [ModelDefinitionProxy]
    #
    # @see https://api.rubyonrails.org/classes/ActiveRecord/ConnectionAdapters/SchemaStatements.html#method-i-create_table Documentation for #create_table in Ruby on Rails
    def create_table table_name, options = {}, &block
      table_name = table_name.to_sym
      @transient_tables << table_name

      ::ActiveRecord::Migration.suppress_messages do
        ::ActiveRecord::Migration.create_table table_name, **options, &block
      end

      # Return a proxy object allowing the caller to chain #define_model
      # right after creating a table so that it can be followed by the model
      # definition.
      ModelDefinitionProxy.new table_name
    end

    # Define a transient Active Record model.
    #
    # Calling this method is roughly equivalent to defining a class inheriting
    # from +ActiveRecord::Base+ with class body defined by the block passed to
    # the method.
    #
    # Transient models must be removed explicitly by calling {.cleanup}.
    #
    # @example
    #   # The following method call ...
    #   TransientRecord.define_model(:User) do
    #     validates :email, presence: true
    #   end
    #
    #   # ... is roughly equivalent to this class definition.
    #   class TransientRecord::Models::User < ActiveRecord::Base
    #     validates :email, presence: true
    #   end
    #
    #
    # @param model_name [String, Symbol] name of model to define.
    # @param base_class [Class] model base class.
    #
    # @yield expects the class body to be passed via the block
    #
    # @return [nil]
    def define_model model_name, base_class = ::ActiveRecord::Base, &block
      # Normally, when a class is defined via `class MyClass < MySuperclass` the
      # .name class method returns the name of the class when called from within
      # the class body. However, anonymous classes defined via Class.new DO NOT
      # HAVE NAMES. They're assigned names when they're assigned to a constant.
      # If we evaluated the class body, passed via block here, in the class
      # definition below then some Active Record macros would break
      # (e.g. has_and_belongs_to_many) due to nil name.
      #
      # We solve the problem by defining an empty model class first, assigning to
      # a constant to ensure a name is assigned, and then reopening the class to
      # give it a non-trivial body.
      klass = Class.new base_class
      Models.const_set model_name, klass

      klass.class_eval(&block) if block_given?

      nil
    end

    # Drop transient tables and models.
    #
    # This method **MUST** be called after every test cases that used Transient
    # Record, as it's responsible for ensuring a clean slate for the next run.
    # It does the following:
    #
    # 1. Remove all models defined via {.define_model}.
    # 2. Drop all tables created via {.create_table}.
    # 3. Start garbage collection.
    #
    # The last step is to ensure model classes are actually removed, and won't
    # appear among the descendants hierarchy of +ActiveRecord::Base+.
    #
    # @return [nil]
    def cleanup
      Models.remove_all_consts

      connection = ::ActiveRecord::Base.connection
      tables_to_remove = @transient_tables
      drop_attempts = tables_to_remove.count * (1 + tables_to_remove.count) / 2

      drop_attempts.times do
        table = tables_to_remove.shift
        break if table.nil?

        begin
          connection.drop_table table, force: :cascade, if_exists: true
        rescue ActiveRecord::InvalidForeignKey, ActiveRecord::StatementInvalid
          # ActiveRecord::StatementInvalid is raised by MySQL when attempting to
          # drop a table that has foreign keys referring to it.
          tables_to_remove << table
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

  # A model definition proxy is a helper class used to implement a fluent
  # interface to callers allowing them to create a table and its corresponding
  # model in close succession. It's marked private as there's no need for
  # callers to access it.
  class ModelDefinitionProxy
    def initialize table_name
      @table_name = table_name.to_s
    end

    def define_model &block
      TransientRecord.define_model @table_name.classify, &block
    end
  end

  private_constant :ModelDefinitionProxy
end

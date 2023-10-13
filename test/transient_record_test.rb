# frozen_string_literal: true

# Base classes that mimic Active Record setup in a Rails app using
# multiple databases.
class ApplicationRecord < ActiveRecord::Base
  if ActiveRecord::VERSION::MAJOR >= 7
    primary_abstract_class
  else
    self.abstract_class = true
  end

  if ActiveRecord::VERSION::MAJOR >= 6
    connects_to database: { writing: :primary }
  end
end

class SecondaryRecord < ApplicationRecord
  self.abstract_class = true

  if ActiveRecord::VERSION::MAJOR >= 6
    connects_to database: { writing: :secondary }
  end
end

ApplicationRecord.establish_connection :primary

# Transient Record contexts used by the test class below.
Context = TransientRecord.context_for ApplicationRecord

# Connect to another database when testing against a version that supports
# multiple databases.
if ActiveRecord::VERSION::MAJOR >= 6
  SecondaryRecord.establish_connection :secondary

  SecondaryContext = TransientRecord.context_for SecondaryRecord
end

class TransientRecordTest < Minitest::Spec
  before do
    @primary_connection   = ApplicationRecord.connection
    @secondary_connection = SecondaryRecord.connection
    TransientRecord.cleanup
  end

  after do
    TransientRecord.cleanup
  end

  describe "Context" do
    describe "#create_table" do
      it "creates temporary table" do
        Context.create_table "users" do |t|
          t.string :email
          t.string :name
        end

        assert_equal %w[users],
                     @primary_connection.tables,
                     "The users table should have been created"
        assert_equal %w[id email name],
                     @primary_connection.columns("users").map(&:name),
                     "The users table should contain the requested columns"
      end

      it "creates temporary tables in multiple contexts" do
        if ActiveRecord::VERSION::MAJOR < 6
          skip("Active Record versions earlier than 6.0 does not support multiple databases")
        end

        Context.create_table "users"
        SecondaryContext.create_table "users"

        assert_equal %w[users],
                     @primary_connection.tables,
                     "The users table should have been created"
        assert_equal %w[users],
                     @secondary_connection.tables,
                     "The users table should have been created"
      end

      it "allows options" do
        # We're passing `id: false` to ensure options are taken into account. The
        # resulting table should _not_ have a primary key column.
        Context.create_table "users", id: false do |t|
          # Since the `id` column is not being created, another column is needed
          # to avoid attempting creating a table without columns.
          t.string :email
        end

        refute @primary_connection.columns("users").any? { |column| column.name == "id" },
               "The users table should not contain the id column, as `id: false` was given"
      end

      it "converts table name to string" do
        Context.create_table :users

        assert_equal %w[users],
                     @primary_connection.tables,
                     "The users table should have been created when its name was a symbol"
      end

      it "allows .define_model call on return value" do
        Context.create_table :users do |t|
          t.string :email
        end.define_model

        assert Context.const_defined?(:User),
               "Context::User should have been defined"
      end
    end

    describe "#define_model" do
      # All test cases need a table, so it's created in advance.
      before do
        Context.create_table :users do |t|
          t.string :email, null: false
        end
      end

      it "defines named model in context" do
        Context.define_model :User

        assert Context.const_defined?(:User),
               "Context::User model should have been defined"
        assert_equal ApplicationRecord,
                     Context::User.superclass,
                     "Context::User should inherit from ActiveRecord::Base, not #{Context::User.superclass.name}"
      end

      it "defines named model with custom base class" do
        Context.define_model :User
        Context.define_model :Admin, Context::User

        assert Context.const_defined?(:Admin),
               "Context::Admin model should have been defined"
        assert_equal Context::User,
                     Context::Admin.superclass,
                     "Context::Admin should be a subclass of Context::User, not #{Context::Admin.superclass.name}"
      end

      it "disallows base classes not inheriting from context base class" do
        assert_raises TransientRecord::Error do
          Context.define_model :User, ActiveRecord::Base
        end
      end

      it "converts model name to symbol" do
        Context.define_model "User"

        assert Context.const_defined?(:User),
               "Model name should have been converted from String to Symbol"
      end

      it "allows model body definition" do
        Context.define_model :User do
          validates :email, presence: true
        end

        user = Context::User.new(email: nil)

        assert user.invalid?,
               "User with nil email should have been marked invalid by the validator from the model body"
        assert_equal ({ email: ["can't be blank"] }),
                     user.errors.to_hash,
                     "User with nil email should have an error caused by the blank email column"
      end
    end

    describe "#cleanup" do
      it "removes all transient tables and models" do
        # A foreign key relationship between tables is added, so that cascading
        # deletion can be tested.
        Context.create_table(:organizations).define_model
        Context.create_table :users do |t|
          t.references :organization, foreign_key: true
        end.define_model

        TransientRecord.cleanup
        remaining_tables = @primary_connection.tables
        remaining_models = Context.constants

        assert remaining_tables.empty?, <<~ERROR
          All temporary tables should have been deleted, but the following still exist:

          #{itemize remaining_tables}
        ERROR
        assert remaining_models.empty?, <<~ERROR
          All models defined in TransientRecord::Models should have been removed, but the following still exist:

          #{itemize remaining_models}
        ERROR
      end

      it "does not remove non-transient tables" do
        begin
          @primary_connection.create_table :users

          TransientRecord.cleanup

          assert @primary_connection.table_exists?(:users),
                 "The non-transient table users should have not been removed"
        ensure
          @primary_connection.drop_table :users, if_exists: true
        end
      end
    end
  end

  def itemize array
    array.map(&:to_s).map { "- #{_1}" }.join("\n")
  end
end

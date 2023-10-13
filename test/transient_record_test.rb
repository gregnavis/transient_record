# frozen_string_literal: true

# Base classes that mimic Active Record setup in a Rails app using
# multiple databases.
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class if respond_to?(:primary_abstract_class)

  connects_to database: { writing: :primary }
end

class PrimaryRecord < ApplicationRecord
  self.abstract_class = true
  connects_to database: { writing: :primary }
end

class SecondaryRecord < ApplicationRecord
  self.abstract_class = true
  connects_to database: { writing: :secondary }
end

ApplicationRecord.establish_connection :primary
PrimaryRecord.establish_connection :primary
SecondaryRecord.establish_connection :secondary

# Transient Record contexts used by the test class below.
PrimaryContext   = TransientRecord.context_for PrimaryRecord
SecondaryContext = TransientRecord.context_for SecondaryRecord

class TransientRecordTest < Minitest::Spec
  before do
    @primary_connection   = PrimaryRecord.connection
    @secondary_connection = SecondaryRecord.connection
    TransientRecord.cleanup
  end

  after do
    TransientRecord.cleanup
  end

  describe "Context" do
    describe "#create_table" do
      it "creates temporary tables in specified contexts" do
        PrimaryContext.create_table "users" do |t|
          t.string :email
          t.string :name
        end
        SecondaryContext.create_table "users" do |t|
          t.integer :age
        end

        assert_equal %w[users],
                     @primary_connection.tables,
                     "The users table should have been created"
        assert_equal %w[id email name],
                     @primary_connection.columns("users").map(&:name),
                     "The users table should contain the requested columns"
        assert_equal %w[users],
                     @secondary_connection.tables,
                     "The users table should have been created"
        assert_equal %w[id age],
                     @secondary_connection.columns("users").map(&:name),
                     "The users table should contain the requested columns"
      end

      it "allows options" do
        # We're passing `id: false` to ensure options are taken into account. The
        # resulting table should _not_ have a primary key column.
        PrimaryContext.create_table "users", id: false do |t|
          # Since the `id` column is not being created, another column is needed
          # to avoid attempting creating a table without columns.
          t.string :email
        end

        refute @primary_connection.columns("users").any? { |column| column.name == "id" },
               "The users table should not contain the id column, as `id: false` was given"
      end

      it "converts table name to string" do
        PrimaryContext.create_table :users

        assert_equal %w[users],
                     @primary_connection.tables,
                     "The users table should have been created when its name was a symbol"
      end

      it "allows .define_model call on return value" do
        PrimaryContext.create_table :users do |t|
          t.string :email
        end.define_model

        assert PrimaryContext.const_defined?(:User),
               "PrimaryContext::User should have been defined"
      end
    end

    describe "#define_model" do
      # All test cases need a table, so it's created in advance.
      before do
        PrimaryContext.create_table :users do |t|
          t.string :email, null: false
        end
      end

      it "defines named model in TransientRecord::Models" do
        PrimaryContext.define_model :User

        assert PrimaryContext.const_defined?(:User),
               "TransientRecord::Models::Primary::User model should have been defined"
        assert_equal PrimaryRecord,
                     PrimaryContext::User.superclass,
                     "TransientRecord::Models::Primary::User should inherit from ActiveRecord::Base, not #{PrimaryContext::User.superclass.name}" # rubocop:disable Layout/LineLength
      end

      it "converts model name to symbol" do
        PrimaryContext.define_model "User"

        assert PrimaryContext.const_defined?(:User),
               "Model name should have been converted from String to Symbol"
      end

      it "allows model body definition" do
        PrimaryContext.define_model :User do
          validates :email, presence: true
        end

        user = PrimaryContext::User.new(email: nil)

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
        PrimaryContext.create_table(:organizations).define_model
        PrimaryContext.create_table :users do |t|
          t.references :organization, foreign_key: true
        end.define_model

        TransientRecord.cleanup
        remaining_tables = @primary_connection.tables
        remaining_models = PrimaryContext.constants

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

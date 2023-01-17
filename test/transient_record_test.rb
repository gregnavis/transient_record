# frozen_string_literal: true

class TransientRecordTest < Minitest::Spec
  before do
    @connection = $database.connection
    TransientRecord.cleanup
  end

  after do
    TransientRecord.cleanup
  end

  describe ".create_table" do
    it "creates temporary table using given options" do
      # We're passing `id: false` to ensure options are taken into account. The
      # resulting table should _not_ have a primary key column.
      TransientRecord.create_table "users", id: false do |t|
        t.string :email
        t.string :name
      end

      assert_equal %w[users], @connection.tables, <<~ERROR
        The users table should have been created
      ERROR
      refute @connection.columns("users").any? { |column| column.name == "id" }, <<~ERROR
        The users table should not contain the id column, as `id: false` was given
      ERROR
      assert_equal %w[email name], @connection.columns("users").map(&:name), <<~ERROR
        The users table should contain the requested columns
      ERROR
    end

    it "converts table name to string" do
      TransientRecord.create_table :users

      assert_equal %w[users], @connection.tables, <<~ERROR
        The users table should have been created when its name was a symbol
      ERROR
    end

    it "allows .define_model call on return value" do
      TransientRecord.create_table :users do |t|
        t.string :email
      end.define_model

      assert TransientRecord::Models.const_defined?(:User), <<~ERROR
        TransientRecord::Models::User should have been defined
      ERROR
    end
  end

  describe ".define_model" do
    # All test cases need a table, so it's created in advance.
    before do
      TransientRecord.create_table :users do |t|
        t.string :email, null: false
      end
    end

    it "defines named model in TransientRecord::Models" do
      TransientRecord.define_model(:User)

      assert TransientRecord::Models.const_defined?(:User), <<~ERROR
        TransientRecord::Models::User should have been defined
      ERROR
      assert_equal ActiveRecord::Base, TransientRecord::Models::User.superclass, <<~ERROR
        TransientRecord::Models::User should inherit from ActiveRecord::Base, not #{TransientRecord::Models::User.superclass.name}
      ERROR
    end

    it "converts model name to symbol" do
      TransientRecord.define_model("User")

      assert TransientRecord::Models.const_defined?(:User), <<~ERROR
        Model name should have been converted from String to Symbol
      ERROR
    end

    it "allows model body definition" do
      TransientRecord.define_model(:User) do
        validates :email, presence: true
      end
      user = TransientRecord::Models::User.new(email: nil)

      assert user.invalid?, <<~ERROR
        User with nil email should have been marked invalid by the validator from the model body
      ERROR
      assert_equal ({ email: ["can't be blank"] }), user.errors.to_hash, <<~ERROR
        User with nil email should have an error caused by the blank email column
      ERROR
    end

    it "allows non-default base class" do
      TransientRecord.define_model(:User, ApplicationRecord)

      assert_equal ApplicationRecord, TransientRecord::Models::User.superclass, <<~ERROR
        TransientRecord::Models::User should inherit from ApplicationRecord, not #{TransientRecord::Models::User.superclass.name}
      ERROR
    end
  end

  describe ".cleanup" do
    it "removes all transient tables and models" do
      # A foreign key relationship between tables is added, so that cascading
      # deletion can be tested.
      TransientRecord.create_table(:organizations).define_model
      TransientRecord.create_table :users do |t|
        t.references :organization, foreign_key: true
      end.define_model

      TransientRecord.cleanup
      remaining_tables = @connection.tables
      remaining_models = TransientRecord::Models.constants

      assert remaining_tables.empty?, <<~ERROR
        All temporary tables should have been deleted, but the following still exist:

        #{itemize remaining_tables}
      ERROR
      assert remaining_models.empty?, <<~ERROR
        All models defined in TransientRecord::Models should have been removed, but the following still exist:

        #{itemize remaining_models}
      ERROR
    end
  end

  def itemize array
    array.map(&:to_s).map { "- #{_1}" }.join("\n")
  end
end

# A class to serve as a base class when testing custom model base classes.
class ApplicationRecord < ActiveRecord::Base; end

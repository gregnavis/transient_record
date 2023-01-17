# frozen_string_literal: true

require "active_record"

class DatabaseConfiguration
  LIBRARY_AND_DATABASE_NAMES = {
    "postgresql" => %w[pg transient_record_test].freeze,
    "mysql2"     => %w[mysql2 transient_record_test].freeze,
    "sqlite3"    => %w[sqlite3 :memory:].freeze
  }.freeze

  def initialize adapter
    if !LIBRARY_AND_DATABASE_NAMES.include?(adapter)
      raise "DATABASE_ADAPTER was set to #{adapter.inspect}, but valid values are:" \
            "" \
            "- postgresql" \
            "- mysql2" \
            "- sqlite3"
    end

    @adapter            = adapter
    @library, @database = LIBRARY_AND_DATABASE_NAMES.fetch(adapter)
  end

  def init
    require @library
  end

  def prepare
    return if @adapter == "sqlite3"

    connect(nil).recreate_database @database
  end

  def connection
    if defined?(@connection)
      @connection
    else
      connect(@database)
      @connection = ActiveRecord::Base.connection
    end
  end

  private

  def connect database
    ActiveRecord::Base.establish_connection(
      adapter:            @adapter,
      use_metadata_table: false,
      database:           database,
      pool:               1
    )
    ActiveRecord::Base.connection
  end
end

# Database-specific initialization.
$database = DatabaseConfiguration.new ENV.fetch("DATABASE_ADAPTER")
$database.init

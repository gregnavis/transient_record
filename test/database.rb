# frozen_string_literal: true

require "active_record"

base_configuration = {
  host:     ENV["DATABASE_HOST"],
  port:     ENV["DATABASE_PORT"],
  username: ENV["DATABASE_USERNAME"],
  password: ENV["DATABASE_PASSWORD"]
}

def downgrade_to_single_database_if_needed configurations
  if ActiveRecord::VERSION::MAJOR >= 6
    configurations
  else
    configurations.slice("primary")
  end
end

DATABASE_CONFIGURATIONS = {
  postgresql: {
    require:        "pg",
    configurations: downgrade_to_single_database_if_needed(
      "primary"   => base_configuration.merge(
        "adapter"  => "postgresql",
        "database" => "transient_record_primary"
      ),
      "secondary" => base_configuration.merge(
        "adapter"  => "postgresql",
        "database" => "transient_record_secondary"
      )
    )
  },
  mysql2:     {
    require:        "mysql2",
    configurations: downgrade_to_single_database_if_needed(
      "primary"   => base_configuration.merge(
        "adapter"  => "mysql2",
        "database" => "transient_record_primary"
      ),
      "secondary" => base_configuration.merge(
        "adapter"  => "mysql2",
        "database" => "transient_record_secondary"
      )
    )
  },
  sqlite3:    {
    require:        "sqlite3",
    configurations: downgrade_to_single_database_if_needed(
      "primary"   => {
        "adapter"  => "sqlite3",
        "database" => ":memory:"
      },
      "secondary" => {
        "adapter"  => "sqlite3",
        "database" => ":memory:"
      }
    )
  }
}.freeze

adapter = ENV.fetch("DATABASE_ADAPTER").to_sym
if !DATABASE_CONFIGURATIONS.include?(adapter)
  # rubocop:disable Layout/LineLength
  raise "DATABASE_ADAPTER was set to #{adapter.inspect}, but valid values are: #{DATABASE_CONFIGURATIONS.keys.map(&:to_s).join(', ')}"
  # rubocop:enable Layout/LineLength
end

adapter_configuration = DATABASE_CONFIGURATIONS[adapter]
require adapter_configuration.fetch(:require)

ActiveRecord::Base.configurations = adapter_configuration.fetch(:configurations)

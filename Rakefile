# frozen_string_literal: true

begin
  require "bundler/setup"
rescue LoadError
  puts "You must `gem install bundler` and `bundle install` to run rake tasks"
end

# YARD

require "yard"

YARD::Rake::YardocTask.new do |t|
  t.options       = %w[]
  t.stats_options = %w[]
end

# Gem tasks

Bundler::GemHelper.install_tasks

# Rubocop

begin
  require "rubocop/rake_task"
rescue LoadError
  # We don't mind not having Rubocop in CI when testing against an older version
  # of Ruby and Rails.
else
  RuboCop::RakeTask.new
end

# Testing

ADAPTERS = %w[postgresql mysql2 sqlite3].freeze

require "rake/testtask"

namespace :env do
  ADAPTERS.each do |adapter|
    desc "Prepare the environment for #{adapter}"
    task(adapter) { ENV["DATABASE_ADAPTER"] = adapter }
  end
end

namespace :db do
  ADAPTERS.each do |adapter|
    desc "Prepare the database for the #{adapter} adapter"
    task adapter => "env:#{adapter}" do
      require_relative "./test/database"
      $database.init
      $database.prepare
    end
  end
end

desc "Prepare the database for all adapters"
task db: ADAPTERS.map { |adapter| "db:#{adapter}" }

namespace :test do
  ADAPTERS.each do |adapter|
    Rake::TestTask.new adapter do |t|
      t.deps      = ["env:#{adapter}"]
      t.libs      = %w[lib]
      t.ruby_opts = %w[-W0 -r./test/run]
      t.pattern   = "test/**/*_test.rb"
      t.verbose   = false
      t.warning   = false # Hide warnings from dependencies.
    end
  end
end

desc "Run the test suite against all adapters"
task test: ADAPTERS.map { |adapter| "test:#{adapter}" }

task default: :test

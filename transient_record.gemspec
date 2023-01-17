# frozen_string_literal: true

$LOAD_PATH.push File.expand_path("lib", __dir__)

require "transient_record"

Gem::Specification.new do |spec|
  spec.name     = "transient_record"
  spec.version  = TransientRecord::VERSION
  spec.authors  = ["Greg Navis"]
  spec.email    = ["contact@gregnavis.com"]
  spec.homepage = "https://github.com/gregnavis/transient_record"
  spec.summary  = "Define transient tables and Active Record models for testing purposes."
  spec.license  = "MIT"
  spec.metadata = { "rubygems_mfa_required" => "true" }
  spec.files    = %w[lib/transient_record.rb MIT-LICENSE.txt README.md]

  spec.required_ruby_version = ">= 2.4.0"

  spec.add_dependency "activerecord", ">= 4.2.0"

  spec.add_development_dependency "mysql2",  "~> 0.5.3"
  spec.add_development_dependency "pg",      "~> 1.1.4"
  spec.add_development_dependency "sqlite3", "~> 1.5.4"
  spec.add_development_dependency "rake",    "~> 12.3.3"
  spec.add_development_dependency "yard",    "~> 0.9.28"
  # We don't install rubocop in CI because we test against older Rubies that
  # are incompatible with Rubocop.
  if ENV["CI"].nil? || ENV["LINT"]
    spec.add_development_dependency "rubocop",      "~> 1.43.0"
    spec.add_development_dependency "rubocop-rake", "~> 0.6.0"
  end
end

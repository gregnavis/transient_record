source "https://rubygems.org"
gemspec path: File.join(File.dirname(__FILE__), "..")

gem "activerecord", "~> 4.2.0"

gem "pg", "<= 0.20"
gem "sqlite3", "~> 1.3.13"

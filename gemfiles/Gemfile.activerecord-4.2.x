source "https://rubygems.org"
gemspec path: File.join(File.dirname(__FILE__), "..")

gem "activerecord", "~> 4.2.0"

# Older versionf of activerecord don't work with newer versions of pg.
gem "pg", "<= 0.20"

source "https://rubygems.org"

gemspec

if RUBY_ENGINE == "jruby"
  gem "jdbc-sqlite3"
else
  gem "sqlite3"
end

gem "rake", "~> 12.0"
gem "matrix" # rack dependency

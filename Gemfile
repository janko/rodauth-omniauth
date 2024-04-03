source "https://rubygems.org"

gemspec

gem "rack", "~> 3.0"
gem "rack-session"

if RUBY_ENGINE == "jruby"
  gem "jdbc-sqlite3"
else
  gem "sqlite3"
end

gem "rake", "~> 12.0"
gem "matrix" # rack dependency

source "https://rubygems.org"

gemspec

if RUBY_VERSION >= "2.4"
  gem "rack", "~> 3.0"
  gem "rack-session"
else
  gem "rack", "~> 2.2"
end

if RUBY_ENGINE == "jruby"
  gem "jdbc-sqlite3"
else
  gem "sqlite3"
end

gem "rake", "~> 12.0"
gem "matrix" # rack dependency

ENV["RACK_ENV"] = "test"

require "bundler/setup"

require "minitest/autorun"
require "minitest/pride"
require "minitest/hooks/default"

require "capybara/dsl"
require "securerandom"

require "sequel"
require "roda"
require "omniauth"
require "bcrypt"
require "rack/session/cookie"
require "rodauth/model"
require "mail"

Mail.defaults { delivery_method :test }

DB = Sequel.connect("#{"jdbc:" if RUBY_ENGINE == "jruby"}sqlite::memory")

DB.create_table :accounts do
  primary_key :id
  String :email, null: false
  String :password_hash
  Integer :status_id, null: false, default: 1
end

DB.create_table :account_identities do
  primary_key :id
  foreign_key :account_id, :accounts
  String :provider, null: false
  String :uid, null: false
  unique [:provider, :uid]
end

DB.create_table :account_verification_keys do
  foreign_key :id, :accounts, primary_key: true
  String :key, null: false
  DateTime :requested_at, null: false, default: Sequel::CURRENT_TIMESTAMP
  DateTime :email_last_sent, null: false, default: Sequel::CURRENT_TIMESTAMP
end

DB.create_table :account_recovery_codes do
  foreign_key :id, :accounts
  String :code
  primary_key [:id, :code]
end

Sequel::Model.cache_anonymous_models = false

OmniAuth.config.allowed_request_methods = %i[get post]
OmniAuth.config.logger = Logger.new(nil)

class Minitest::HooksSpec
  include Capybara::DSL

  private

  attr_reader :app

  def app=(app)
    @app = Capybara.app = app
  end

  def rodauth(&block)
    @rodauth_block = block
  end

  def roda(sessions: :plugin, **options, &block)
    app = Class.new(Roda)
    case sessions
    when :plugin
      app.plugin :sessions, secret: SecureRandom.hex(32)
    when :rack
      app.use Rack::Session::Cookie, secret: SecureRandom.hex(32)
    end
    app.plugin :render, layout_opts: { path: "test/views/layout.str" }

    rodauth_block = @rodauth_block
    app.plugin :rodauth, **options do
      instance_exec(&rodauth_block)
      account_password_hash_column :password_hash
      skip_status_checks? false
      set_deadline_values? true
    end
    app.route(&block)

    self.app = app
  end

  def omniauth_login(path = nil, name: "Janko", email: "janko@hey.com")
    visit path if path
    fill_in "Name", with: name
    fill_in "Email", with: email
    click_on "Sign In"
  end

  def login(email: "janko@hey.com", password: "secret")
    visit "/login"
    fill_in "Login", with: email
    fill_in "Password", with: password
    click_on "Login"
  end

  def logout
    visit "/logout"
    click_on "Logout"
  end

  around do |&block|
    DB.transaction(rollback: :always, auto_savepoint: true) { super(&block) }
  end

  after do
    Capybara.reset_sessions!
  end
end

class RedirectStrategy
  include OmniAuth::Strategy

  def request_phase
    redirect "/external/auth"
  end
end

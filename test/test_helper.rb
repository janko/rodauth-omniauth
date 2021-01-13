ENV["RACK_ENV"] = "test"

require "bundler/setup"

require "minitest/autorun"
require "minitest/pride"
require "minitest/hooks/default"

require "capybara/dsl"
require "securerandom"

require "sequel/core"
require "roda"
require "omniauth"
require "bcrypt"

DB = Sequel.sqlite

DB.create_table :accounts do
  primary_key :id
  String :email, null: false
  String :password_hash
  Integer :status_id, null: false, default: 2
end

DB.create_table :account_identities do
  primary_key :id
  foreign_key :account_id, :accounts
  String :provider, null: false
  String :uid, null: false
  json :info, null: false, default: "{}"
  json :credentials, null: false, default: "{}"
  json :extra, null: false, default: "{}"
  unique [:provider, :uid]
end

OmniAuth.config.logger = Logger.new(nil)

class OmniAuth::Strategies::Developer
  # monkey patch to include script name in form action path
  def request_phase
    form = OmniAuth::Form.new(:title => 'User Info', :url => script_name + callback_path)
    options.fields.each do |field|
      form.text_field field.to_s.capitalize.tr('_', ' '), field.to_s
    end
    form.button 'Sign In'
    form.to_response
  end
end

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

  def roda(session: :middleware, &block)
    app = Class.new(Roda)
    case session
    when :middleware
      app.use RodaSessionMiddleware, secret: SecureRandom.hex(32)
    when :plugin
      app.plugin :sessions, secret: SecureRandom.hex(32)
    end
    app.plugin :render, layout_opts: { path: "test/views/layout.str" }

    rodauth_block = @rodauth_block
    app.plugin :rodauth do
      instance_exec(&rodauth_block)
      account_password_hash_column :password_hash
      skip_status_checks? false
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

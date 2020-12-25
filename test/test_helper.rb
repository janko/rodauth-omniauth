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

DB = Sequel.sqlite

DB.create_table :accounts do
  primary_key :id
  String :email, null: false
  String :password_hash
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

  def roda(&block)
    app = Class.new(Roda)
    app.use Rack::Session::Cookie, secret: "secret"
    app.plugin :render, layout_opts: { path: "test/views/layout.str" }

    rodauth_block = @rodauth_block
    app.plugin :rodauth do
      instance_exec(&rodauth_block)
      account_password_hash_column :password_hash
    end
    app.route(&block)

    self.app = app
  end

  def login(name: "Janko", email: "janko@hey.com")
    fill_in "Name", with: name
    fill_in "Email", with: email
    click_on "Sign In"
  end

  around do |&block|
    DB.transaction(rollback: :always, auto_savepoint: true) { super(&block) }
  end

  after do
    Capybara.reset_sessions!
  end
end

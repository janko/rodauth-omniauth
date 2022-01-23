require "test_helper"

describe "Rodauth omniauth feature" do
  before do
    DB[:accounts].insert(
      email: "janko@hey.com",
      password_hash: BCrypt::Password.create("secret", cost: 1),
    )
  end

  it "connects new external identities for logged in account" do
    rodauth do
      enable :omniauth
      omniauth_provider :developer
    end
    roda do |r|
      r.rodauth
      r.root { view content: rodauth.authenticated_by.join(",") }
    end

    login
    omniauth_login "/auth/developer", name: "Janko", email: "janko@other.com"
    assert_equal "The external identity has been connected", page.find("#notice_flash").text
    assert_match "password", page.html

    assert_equal [{
      id:          1,
      account_id:  1,
      provider:    "developer",
      uid:         "janko@other.com",
      info:        '{"name":"Janko","email":"janko@other.com"}',
      credentials: '{}',
      extra:       '{}',
    }], DB[:account_identities].all
  end

  it "handles existing external identities for logged in account" do
    rodauth do
      enable :omniauth, :logout
      omniauth_provider :developer
    end
    roda do |r|
      r.rodauth
      r.on("auth") { r.omniauth }
      r.root { view content: rodauth.authenticated_by.join(",") }
    end

    login
    omniauth_login "/auth/developer", email: "janko@other.com"
    logout

    login
    omniauth_login "/auth/developer", email: "janko@other.com"
    assert_equal "The external identity has been connected", page.find("#notice_flash").text
    assert_match "password", page.html
  end

  it "logs in account already connected to an external identity" do
    DB[:accounts].insert(email: "janko@other.com")

    rodauth do
      enable :omniauth, :logout
      omniauth_provider :developer
    end
    roda do |r|
      r.rodauth
      r.on("auth") { r.omniauth }
      r.root { view content: "#{rodauth.authenticated_by.join(",")} - #{rodauth.session_value}" }
    end

    login
    omniauth_login "/auth/developer", email: "janko@other.com"
    logout

    omniauth_login "/auth/developer", email: "janko@other.com"
    assert_equal "You have been logged in", page.find("#notice_flash").text
    assert_match "omniauth - 1", page.html
  end

  it "logs in account with the email address matching external identity" do
    rodauth do
      enable :omniauth
      omniauth_provider :developer
    end
    roda do |r|
      r.rodauth
      r.on("auth") { r.omniauth }
      r.root { view content: rodauth.authenticated_by.join(",") }
    end

    omniauth_login "/auth/developer"
    assert_equal "You have been logged in", page.find("#notice_flash").text
    assert_match "omniauth", page.html
  end

  it "doesn't log in unopen accounts" do
    DB[:accounts].update(status_id: 1)

    rodauth do
      enable :omniauth
      omniauth_provider :developer
    end
    roda do |r|
      r.rodauth
      r.on("auth") { r.omniauth }
      r.root { view content: "Logged in: #{!!rodauth.logged_in?}" }
    end

    omniauth_login "/auth/developer"
    assert_equal "There was an error logging in (unverified account, please verify account before logging in)", page.find("#error_flash").text
    assert_match "Logged in: false", page.html
  end

  it "creates new accounts from external identity" do
    DB[:accounts].delete

    rodauth do
      enable :omniauth
      omniauth_provider :developer
    end
    roda do |r|
      r.rodauth
      r.on("auth") { r.omniauth }
      r.root { view content: rodauth.authenticated_by.join(",") }
    end

    omniauth_login "/auth/developer", email: "janko@hey.com"
    assert_equal "Your account has been created", page.find("#notice_flash").text
    assert_match "omniauth", page.html

    assert_equal "janko@hey.com", DB[:accounts].first[:email]
    assert_equal "janko@hey.com", DB[:account_identities].first[:uid]
  end

  it "connects external identities belonging to other account" do
    DB[:accounts].insert(
      email: "janko@other.com",
      password_hash: BCrypt::Password.create("secret", cost: 1)
    )

    rodauth do
      enable :omniauth, :logout
      omniauth_provider :developer
    end
    roda do |r|
      r.rodauth
      r.on("auth") { r.omniauth }
      r.root { view content: "" }
    end

    login(email: "janko@other.com")
    omniauth_login "/auth/developer", email: "janko@other.com"
    logout

    login(email: "janko@hey.com")
    omniauth_login "/auth/developer", email: "janko@other.com"
    assert_equal "The external identity has been connected", page.find("#notice_flash").text

    assert_equal 1, DB[:account_identities].count
    assert_equal 1, DB[:account_identities].first[:account_id]
  end

  it "updates existing external identities with new data" do
    rodauth do
      enable :omniauth
      omniauth_provider :developer
    end
    roda do |r|
      r.rodauth
      r.on("auth") { r.omniauth }
      r.root { view content: "" }
    end

    omniauth_login "/auth/developer", name: "Janko", email: "janko@hey.com"
    omniauth_login "/auth/developer", name: "New Name", email: "janko@hey.com"

    assert_equal '{"name":"New Name","email":"janko@hey.com"}', DB[:account_identities].first[:info]
  end

  it "deletes omniauth identities when account is closed" do
    rodauth do
      enable :omniauth, :close_account
      omniauth_provider :developer
    end
    roda do |r|
      r.rodauth
      r.on("auth") { r.omniauth }
      r.root { view content: "" }
    end

    omniauth_login "/auth/developer"

    visit "/close-account"
    fill_in "Password", with: "secret"
    click_on "Close"

    assert DB[:account_identities].empty?
  end

  it "adds omniauth login links to login form footer" do
    rodauth do
      enable :omniauth
      omniauth_strategies :foo => :developer, :bar => :developer
      omniauth_provider :foo
      omniauth_provider :bar
    end
    roda do |r|
      r.rodauth
    end

    visit "/login"
    assert_match %(<a href="/auth/foo">Login via Foo</a>), page.html
    assert_match %(<a href="/auth/bar">Login via Bar</a>), page.html
  end

  it "supports retrieving connected omniauth identities" do
    identities = nil

    rodauth do
      enable :omniauth
      omniauth_provider :developer
    end
    roda do |r|
      r.on("auth") { r.omniauth }
      r.root do
        identities = rodauth.get_omniauth_identities
        view content: rodauth.omniauth_connected_providers.inspect
      end
    end

    omniauth_login "/auth/developer"

    assert_match "[:developer]", page.html

    assert_equal "developer", identities[0][:provider]
    assert_equal 1, identities[0][:account_id]
  end

  it "adds omniauth to possible authentication methods" do
    rodauth do
      enable :omniauth
      omniauth_provider :developer
    end
    roda do |r|
      r.rodauth
      r.on("auth") { r.omniauth }
      r.root { rodauth.possible_authentication_methods.join(",") }
    end

    login
    assert_equal "password", page.html

    DB[:accounts].update(password_hash: nil)
    visit "/"
    assert_equal "", page.html

    omniauth_login "/auth/developer"
    assert_equal "omniauth", page.html
  end

  it "works correctly with #two_factor_authentication_setup? without password" do
    DB.create_table :account_recovery_codes do
      foreign_key :id, :accounts
      String :code
      primary_key [:id, :code]
    end

    rodauth do
      enable :omniauth, :recovery_codes
      omniauth_provider :developer
    end
    roda do |r|
      r.rodauth
      r.on("auth") { r.omniauth }
      r.root { "MFA setup: #{rodauth.two_factor_authentication_setup?}" }
    end

    omniauth_login "/auth/developer"
    assert_equal "MFA setup: false", page.html

    DB[:accounts].update(password_hash: nil)
    visit "/"
    assert_equal "MFA setup: false", page.html

    DB[:account_recovery_codes].insert(id: 1, code: "code")
    visit "/"
    assert_equal "MFA setup: true", page.html
  end
end

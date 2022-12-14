require "test_helper"

describe "Rodauth omniauth feature" do
  before do
    DB[:accounts].insert(
      email: "janko@hey.com",
      password_hash: BCrypt::Password.create("secret", cost: 1),
      status_id: 2,
    )
  end

  it "creates new accounts from external identity" do
    rodauth do
      enable :omniauth
      omniauth_provider :developer
    end
    roda do |r|
      r.rodauth
      r.root { view content: rodauth.authenticated_by.join(",") }
    end

    omniauth_login "/auth/developer", email: "janko@other.com"
    assert_equal "You have been logged in", page.find("#notice_flash").text
    assert_match "omniauth", page.html

    account = DB[:accounts].order(:id).last
    assert_equal "janko@other.com", account[:email]
    assert_equal 2, account[:status_id]

    identity = DB[:account_identities].first
    assert_equal "janko@other.com", identity[:uid]
    assert_equal account[:id], identity[:account_id]
  end

  it "logs in account already connected to an external identity" do
    DB[:account_identities].insert(account_id: 1, provider: "developer", uid: "janko@other.com")
    DB[:accounts].insert(email: "janko@other.com", status_id: 2)

    rodauth do
      enable :omniauth, :logout
      omniauth_provider :developer
    end
    roda do |r|
      r.rodauth
      r.root { view content: "#{rodauth.authenticated_by.join(",")} - #{rodauth.session_value}" }
    end

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
      r.root { view content: rodauth.authenticated_by.join(",") }
    end

    omniauth_login "/auth/developer"
    assert_equal "You have been logged in", page.find("#notice_flash").text
    assert_match "omniauth", page.html
    assert_equal 1, DB[:accounts].count
  end

  it "doesn't log in unverified accounts" do
    DB[:accounts].update(status_id: 1)

    rodauth do
      enable :omniauth
      omniauth_provider :developer
    end
    roda do |r|
      r.rodauth
      r.root { view content: "Logged in: #{!!rodauth.logged_in?}" }
    end

    omniauth_login "/auth/developer"
    assert_equal "The account matching the external identity is currently awaiting verification", page.find("#error_flash").text
    assert_equal "/login", page.current_path

    visit "/"
    assert_includes page.html, "Logged in: false"
  end

  it "updates existing external identities with new data" do
    DB.add_column :account_identities, :info, :json, default: "{}"

    rodauth do
      enable :omniauth
      omniauth_provider :developer
      omniauth_identity_update_hash do
        { info: omniauth_info.to_json }
      end
    end
    roda do |r|
      r.rodauth
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
      r.root { view content: "" }
    end

    omniauth_login "/auth/developer"

    visit "/close-account"
    fill_in "Password", with: "secret"
    click_on "Close"
    assert DB[:account_identities].empty?

    omniauth_login "/auth/developer"
    assert_equal 2, DB[:accounts].count
  end

  it "adds omniauth to possible authentication methods" do
    rodauth do
      enable :omniauth
      omniauth_provider :developer
    end
    roda do |r|
      r.rodauth
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

    DB.create_table :account_email_auth_keys do
      foreign_key :id, :accounts, primary_key: true, type: :Bignum
      String :key, null: false
      DateTime :deadline, null: false
      DateTime :email_last_sent, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    rodauth do
      enable :omniauth, :recovery_codes, :email_auth
      omniauth_provider :developer
    end
    roda do |r|
      r.rodauth
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

  it "allows modifying created account" do
    DB.add_column :accounts, :name, String

    rodauth do
      enable :omniauth
      omniauth_provider :developer
      before_omniauth_create_account { account[:name] = omniauth_info[:name] }
    end
    roda do |r|
      r.rodauth
      r.root { view content: rodauth.authenticated_by.join(",") }
    end

    omniauth_login "/auth/developer", name: "Name", email: "janko@other.com"
    account = DB[:accounts].order(:id).last
    assert_equal "Name", account[:name]
  end

  it "allows retrieving created omniauth strategy before login" do
    identity_id = nil
    rodauth do
      enable :omniauth
      omniauth_provider :developer
      before_login { identity_id = omniauth_identity_id }
    end
    roda do |r|
      r.rodauth
      r.root { view content: rodauth.authenticated_by.join(",") }
    end

    omniauth_login "/auth/developer"
    assert_equal 1, identity_id
  end

  it "disallows being used as 2nd factor with password authentication" do
    rodauth do
      enable :omniauth, :confirm_password
      omniauth_provider :developer
    end
    roda do |r|
      r.rodauth
      rodauth.require_password_authentication
      r.root { rodauth.authenticated_by.join(",") }
    end

    omniauth_login "/auth/developer"
    assert_equal "/confirm-password", page.current_path

    fill_in "Password", with: "secret"
    click_on "Confirm Password"
    assert_equal "password", page.html
  end

  it "has translations" do
    DB[:accounts].update(status_id: 1)

    rodauth do
      enable :omniauth, :i18n
      omniauth_provider :developer
    end
    roda do |r|
      r.rodauth
      r.root { view content: "" }
    end

    omniauth_login "/auth/developer"
    assert_equal "The account matching the external identity is currently awaiting verification", page.find("#error_flash").text
  end
end

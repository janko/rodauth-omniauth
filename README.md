# rodauth-omniauth

[Rodauth] feature that offers login and registration via multiple external providers using [OmniAuth], together with the persistence of external identities.

## Installation

Add the gem to your project:

```sh
$ bundle add rodauth-omniauth
```

## Usage

You'll first need to create the table for storing external identities:

```rb
Sequel.migration do
  change do
    create_table :account_identities do
      primary_key :id
      foreign_key :account_id, :accounts
      String :provider, null: false
      String :uid, null: false
      unique [:provider, :uid]
    end
  end
end
```
```rb
class CreateAccountIdentities < ActiveRecord::Migration
  def change
    create_table :account_identities do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :provider, null: false
      t.string :uid, null: false
      t.index [:provider, :uid], unique: true
    end
  end
end
```

Then enable the `omniauth` feature and register providers in your Rodauth configuration:

```sh
$ bundle add omniauth-facebook omniauth-twitter, omniauth-google_oauth2
```
```rb
plugin :rodauth do
  enable :omniauth

  omniauth_provider :facebook, ENV["FACEBOOK_APP_ID"], ENV["FACEBOOK_APP_SECRET"], scope: "email"
  omniauth_provider :twitter, ENV["TWITTER_API_KEY"], ENV["TWITTER_API_SECRET"]
  omniauth_provider :google_oauth2, ENV["GOOGLE_CLIENT_ID"], ENV["GOOGLE_CLIENT_SECRET"], name: :google
end
```

You can now add authentication links to your login form:

```erb
<!-- app/views/rodauth/_login_form_footer.html.erb -->
<!-- ... -->
  <li><%= button_to "Login via Facebook", rodauth.omniauth_request_path(:facebook), method: :post, data: { turbo: false }, class: "btn btn-link p-0" %></li>
  <li><%= button_to "Login via Twitter", rodauth.omniauth_request_path(:twitter), method: :post, data: { turbo: false }, class: "btn btn-link p-0" %></li>
  <li><%= button_to "Login via Google", rodauth.omniauth_request_path(:google), method: :post, data: { turbo: false }, class: "btn btn-link p-0" %></li>
<!-- ... -->
```

Assuming you configured the providers correctly, you should now be able to authenticate via an external provider. The `omniauth` feature handles the callback request, automatically creating new identities and verified accounts from those identities as needed.

```rb
DB[:accounts].all
#=> [{ id: 123, status_id: 2, email: "user@example.com" }]
DB[:account_identities].all
#=> [{ id: 456, account_id: 123, provider: "facebook", uid: "984346198764" },
#    { id: 789, account_id: 123, provider: "google", uid: "5871623487134"}]
```

Currently, provider login is required to return the user's email address, and account creation is assumed not to require additional fields that need to be entered manually. There is currently also no built-in functionality for connecting/removing external identities when signed in. Both features are planned for future versions.

### Login

After provider login, you can perform custom logic at the start of the request:

```rb
before_omniauth_callback_route do
  omniauth_provider #=> :google
end
```

If the external identity doesn't already exist, and there is an account with email matching the identity's, the new identity will be assigned to that account.

If the local account associated to the external identity exists and is unverified (e.g. it was created through normal registration), the external login will abort during the callback phase. You can change the default error flash and redirect location in this case:

```rb
omniauth_login_unverified_account_error_flash "The account matching the external identity is currently awaiting verification"
omniauth_login_failure_redirect { require_login_redirect }
```

### Account creation

Since provider accounts have verified the email address, local accounts created via external logins are automatically considered verified.

If you want to use extra user information for account creation, you can do so via hooks:

```rb
before_omniauth_create_account { account[:name] = omniauth_name }
# or
after_omniauth_create_account do
  Profile.create(account_id: account_id, bio: omniauth_info["description"], image_url: omniauth_info["image"])
end
```

When the account is closed, its external identities are automatically deleted from the database.

### Identity data

You can also store extra data on the external identities. For example, we could override the update hash to store `info`, `credentials`, and `extra` data from the auth hash into separate columns:

```rb
alter_table :account_identities do
  add_column :info, :json, default: "{}"
  add_column :credentials, :json, default: "{}"
  add_column :extra, :json, default: "{}"
end
```
```rb
# this data will be refreshed on each login
omniauth_identity_update_hash do
  {
    info: omniauth_info.to_json,
    credentials: omniauth_credentials.to_json,
    extra: omniauth_extra.to_json,
  }
end
```

With this configuration, the identity record will be automatically synced with most recent state on each provider login. If you would like to only save provider data on first login, you can override the insert hash instead:

```rb
# this data will be stored only on first login
omniauth_identity_insert_hash do
  super().merge(
    info: omniauth_info.to_json,
    credentials: omniauth_credentials.to_json,
    extra: omniauth_extra.to_json,
  }
end
```

### Model associations

When using the [rodauth-model] gem, an `identities` one-to-many association will be defined on the account model:

```rb
require "rodauth/model"

class Account < Sequel::Model
  include Rodauth::Model(RodauthApp.rodauth)
end
```
```rb
Account.first.identities #=>
# [
#   #<Account::Identity id=123 provider="facebook" uid="987434628">,
#   #<Account::Identity id=456 provider="google" uid="274673644">
# ]
```

## Base

The `omniauth` feature builds on top of the `omniauth_base` feature, which sets up OmniAuth and routes its requests, but has no interaction with the database. So, if you would prefer to handle external logins differently, you can load just the `omniauth_base` feature, and implement your own callbacks.

```rb
plugin :rodauth do
  enable :omniauth_base

  omniauth_provider :github, ENV["GITHUB_KEY"], ENV["GITHUB_SECRET"], scope: "user"
  omniauth_provider :apple, ENV["CLIENT_ID"], { scope: "email name", ... }
end

route do |r|
  r.rodauth # routes Rodauth and OmniAuth requests

  r.get "auth", String, "callback" do
    # ... handle callback request ...
  end
end
```

### Helpers

There are various helper methods available for reading OmniAuth data:

```rb
# retrieving the auth hash:
rodauth.omniauth_auth #=> { "provider" => "twitter", "uid" => "49823724", "info" => { "email" => "user@example.com", "name" => "John Smith", ... }, ... }
rodauth.omniauth_provider #=> "twitter"
rodauth.omniauth_uid #=> "49823724"
rodauth.omniauth_info #=> { "email" => "user@example.com", "name" => "John Smith", ... }
rodauth.omniauth_email #=> "user@example.com"
rodauth.omniauth_name #=> "John Smith"
rodauth.omniauth_credentials #=> returns "credentials" value from auth hash
rodauth.omniauth_extra #=> returns "extra" value from auth hash

# retrieving additional information:
rodauth.omniauth_strategy #=> #<OmniAuth::Strategies::Twitter ...>
rodauth.omniauth_params # returns GET params from request phase
rodauth.omniauth_origin # returns origin from request phase (usually referrer)

# retrieving error information in case of a login failure
rodauth.omniauth_error # returns the exception object
rodauth.omniauth_error_type # returns the error type symbol (strategy-specific)
rodauth.omniauth_error_strategy # returns the strategy for which the error occured
```

### URLs

URL helpers are provided as well:

```rb
rodauth.prefix #=> "/user"
rodauth.omniauth_prefix #=> "/auth"

rodauth.omniauth_request_route(:facebook) #=> "auth/facebook"
rodauth.omniauth_request_path(:facebook) #=> "/user/auth/facebook"
rodauth.omniauth_request_url(:facebook) #=> "https://example.com/user/auth/facebook"

rodauth.omniauth_callback_route(:facebook) #=> "auth/facebook/callback"
rodauth.omniauth_callback_path(:facebook) #=> "/user/auth/facebook/callback"
rodauth.omniauth_callback_url(:facebook) #=> "https://example.com/user/auth/facebook/callback"
```

The prefix for the OmniAuth app can be changed:

```rb
omniauth_prefix "/external"
```

### Hooks

OmniAuth configuration has global hooks for various phases, which get called with the Rack env hash. Here you can use corresponding Rodauth configuration methods, which are executed in Rodauth context:

```rb
omniauth_setup { ... }
omniauth_request_validation_phase { ... }
omniauth_before_request_phase { ... }
omniauth_before_callback_phase { ... }
omniauth_on_failure { ... }
```

You can use the `omniauth_strategy` helper method to differentiate between strategies:

```rb
omniauth_setup do
  if omniauth_strategy.name == :github
    omniauth_strategy.options[:foo] = "bar"
  end
end
```

#### Failure

The default reaction to login failure is to redirect to the root page with an error flash message. You can change the configuration:

```rb
omniauth_failure_error_flash "There was an error logging in with the external provider"
omniauth_failure_redirect { default_redirect }
omniauth_failure_error_status 500 # for JSON API
```

Or provide your own implementation:

```rb
omniauth_on_failure do
  case omniauth_error_type
  when :no_authorization_code then # ...
  when :uknown_signature_algorithm then # ...
  else # ...
  end
end
```

#### CSRF protection

The default request validation phase uses Rodauth's configured CSRF protection, so there is no need for external gems such as `omniauth-rails_csrf_protection`.

### Inheritance

The registered providers are inherited between Rodauth auth classes, so you can have fine-grained configuration for different account types.

```rb
class RodauthBase < Rodauth::Auth
  configure do
    enable :omniauth_base
    omniauth_provider :google_oauth2, ...
  end
end
```
```rb
class RodauthMain < RodauthBase
  configure do
    omniauth_provider :facebook, ...
  end
end
```
```rb
class RodauthAdmin < RodauthBase
  configure do
    omniauth_provider :twitter, ...
    omniauth_provider :github, ...
  end
end
```
```rb
class RodauthApp < Roda
  plugin :rodauth, auth_class: RodauthMain
  plugin :rodauth, auth_class: RodauthAdmin, name: :admin
end
```
```rb
rodauth.omniauth_providers #=> [:google_oauth2, :facebook]
rodauth(:admin).omniauth_providers #=> [:google_oauth2, :twitter, :github]
```

### JSON

JSON requests are supported for the request and callback phases. The request phase endpoint will return the authorize URL:

```http
POST /auth/facebook
Accept: application/json
Content-Type: application/json
```
```http
200 OK
Content-Type: application/json

{ "authorize_url": "https://external.com/login" }
```

If there was a login failure, the error type will be included in the response:

```http
POST /auth/facebook/callback
Accept: application/json
Content-Type: application/json
```
```http
500 Internal Server Error
Content-Type: application/json

{ "error_type": "some_error", "error": "There was an error logging in with the external provider" }
```

You can change authorize URL and error type keys:

```rb
omniauth_authorize_url_key "authorize_url"
omniauth_error_type_key "error_type"
```

### JWT

JWT requests are supported for the request and callback phases. OmniAuth information will be stored in JWT session data during the request phase, and restored during the callback phase, as long as the updated JWT token is passed.

## Development

Run tests with Rake:

```sh
$ bundle exec rake test
```

## Credits

The implementation of this gem was inspired by [this OmniAuth guide](https://github.com/omniauth/omniauth/wiki/Managing-Multiple-Providers).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the rodauth-omniauth project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/janko/rodauth-pwned/blob/master/CODE_OF_CONDUCT.md).

[Rodauth]: https://github.com/jeremyevans/rodauth
[OmniAuth]: https://github.com/omniauth/omniauth
[rodauth-model]: https://github.com/janko/rodauth-model

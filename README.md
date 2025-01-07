# rodauth-omniauth

[Rodauth] feature that offers login and registration via multiple external providers using [OmniAuth], together with the persistence of external identities.

It comes with many features out of the box:

* multiple external providers (with automatic identity linking)
* automatic account creation (or login-only)
* email verification on login
* ability to count as two factors
* JSON API support (+ JWT)
* per-configuration strategies with inheritance

## Installation

Add the gem to your project:

```sh
$ bundle add rodauth-omniauth
```

> [!NOTE]
> Rodauth's CSRF protection will be used for the request validation phase, so there is no need for gems like `omniauth-rails_csrf_protection`.


## Getting started

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
$ bundle add omniauth-facebook omniauth-twitter, omniauth-google-oauth2
```
```rb
# in your Rodauth configuration
enable :omniauth

omniauth_provider :facebook, ENV["FACEBOOK_APP_ID"], ENV["FACEBOOK_APP_SECRET"], scope: "email"
omniauth_provider :twitter, ENV["TWITTER_API_KEY"], ENV["TWITTER_API_SECRET"]
omniauth_provider :google_oauth2, ENV["GOOGLE_CLIENT_ID"], ENV["GOOGLE_CLIENT_SECRET"], name: :google
```

> [!WARNING]
> The `rodauth-omniauth` gem requires OmniAuth 2.x, so it's only compatible with providers gems that support it.

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
Account.all
#=> [#<Account @values={ id: 123, status_id: 2, email: "user@example.com" }>]
Account::Identity.all
#=> [#<Account::Identity @values={ id: 456, account_id: 123, provider: "facebook", uid: "984346198764" }>,
#    #<Account::Identity @values={ id: 789, account_id: 123, provider: "google", uid: "5871623487134"}>]
```

The example above assumes you're using [rodauth-model] (automatically setup with [rodauth-rails]), which will define `Account::Identity` model for the `account_identities` table, along with the `identities` association on the `Account` model.

```rb
account = Account.first
account.identities #=> [#<Account::Identity ...>, ...]
```

Currently, provider login is required to return the user's email address, and account creation is assumed not to require additional fields that need to be entered manually. There is currently also no built-in functionality for connecting/removing external identities when signed in. Both features are planned for future versions.

## Configuration reference

### Auth Value Methods

| Method | Description |
| :----  | :---------- |
| `omniauth_verify_account?` | Automatically verify unverified accounts on login (defaults to true). |
| `omniauth_login_unverified_account_error_flash` | Flash message for when existing account is unverified and automatic verification is disabled. |
| `omniauth_login_failure_redirect` | Redirect location for when OmniAuth login failed. |
| `omniauth_create_account?` | Automatically create account for new email address on OmniAuth login (defaults to true). |
| `omniauth_login_no_matching_account_error_flash` | Flash message for when no existing account was found and automatic creation is disabled. |
| `omniauth_two_factors?` | Treat OmniAuth login as two factors when using MFA (defaults to false). |
| `omniauth_identities_table` | Table name for external identities (defaults to `account_identities`). |
| `omniauth_identities_id_column` | Primary key column for identities table (defaults to `id`). |
| `omniauth_identities_account_id_column` | Foreign key column for identities table (defaults to `account_id`). |
| `omniauth_identities_provider_column` | Provider column for identities table (defaults to `provider`). |
| `omniauth_identities_uid_column` | UID column for identities table (defaults to `uid`). |
| `omniauth_prefix` | Path prefix to use for OmniAuth routes (defaults to `/auth`). |
| `omniauth_failure_error_flash` | Flash message for failed OmniAuth login. |
| `omniauth_failure_redirect` | Redirect location for failed OmniAuth login. |
| `omniauth_failure_error_status` | Response status for failed OmniAuth login (defaults to 500). |
| `omniauth_authorize_url_key` | Field name for authorization URL in JSON mode. |
| `omniauth_error_type_key` | Field name for error type in JSON mode. |

### Auth Methods

| Method | Description |
| :----  | :---------- |
| `account_from_omniauth` | Find an existing account from OmniAuth login data (by default matches by email). |
| `before_omniauth_callback_route` | Run arbitrary code before handling the callback route. |
| `omniauth_identity_insert_hash` | Hash of column values used for creating a new identity on login. |
| `omniauth_identity_update_hash` | Hash of column values used fro updating existing identities on login. |
| `before_omniauth_create_account` | Any actions to take before creating a new account on OmniAuth login. |
| `after_omniauth_create_account` | Any actions to take after creating a new account on OmniAuth login. |
| `omniauth_setup` | Hook for OmniAuth setup phase |
| `omniauth_request_validation_phase` | Hook for OmniAuth request validation phase (defaults to CSRF protection). |
| `omniauth_before_request_phase` | Hook for OmniAuth before request phase. |
| `omniauth_before_callback_phase` | Hook for OmniAuth  before callback phase. |
| `omniauth_on_failure` | Hook for OmniAuth login failure. |

## Customizing

### Login

After provider login, you can perform custom logic at the start of the callback request:

```rb
before_omniauth_callback_route do
  omniauth_provider #=> :google
end
```

If the external identity doesn't already exist, and there is an account with email matching the identity's, the new identity will be assigned to that account. You can change how existing accounts are searched after provider login:

```rb
account_from_omniauth do
  account_table_ds.first(email: omniauth_email) # roughly the default implementation
end
# or
account_from_omniauth {} # disable finding existing accounts for new identities
```

#### Account verification

If the account associated to the external identity exists and is unverified (e.g. it was created through normal registration), the callback phase will automatically verify the account and login, assuming the `verify_account` feature is enabled and external email is the same.

If you wish to disallow OmniAuth login into unverified accounts, set the following:

```rb
omniauth_verify_account? false
```

You can change the default error flash and redirect location in this case:

```rb
omniauth_login_unverified_account_error_flash "The account matching the external identity is currently awaiting verification"
omniauth_login_failure_redirect { require_login_redirect }
```

### Account creation

Accounts created via external login are automatically verified, because it's assumed your email address was verified by the external provider. If you want to add extra user information to created accounts, you can do so via hooks:

```rb
before_omniauth_create_account { account[:name] = omniauth_name }
# or
after_omniauth_create_account do
  Profile.create(account_id: account_id, bio: omniauth_info["description"], image_url: omniauth_info["image"])
end
```

You might want to disable automatic account creation in certain cases. For example, if you're showing OmniAuth login links on both login and registration pages, you might want OmniAuth login on the login page to only log into existing accounts. You could configure this so that it's controlled via a query parameter:

```rb
# somewhere in your view template:
rodauth.omniauth_request_path(:google, action: "login") #=> "/auth/github?action=login"
```
```rb
# in your Rodauth configuration:
omniauth_create_account? { omniauth_params["action"] != "login" }
```

You can change the default error message for when existing account wasn't found in case automatic account creation is disabled:

```rb
omniauth_login_no_matching_account_error_flash "No existing account found"
```

### Multifactor authentication

By default, OmniAuth login will count only as one factor. So, if the user has multifactor authentication enabled, they will be asked to authenticate with 2nd factor when required.

If you're using OmniAuth login for SSO and want to rely on 2FA policies set on the external provider, you can have OmniAuth login count as two factors:

```rb
omniauth_two_factors? true
```

You can also make it conditional based on data from the external provider:

```rb
omniauth_two_factors? do
  # only count as two factors if external account uses 2FA
  omniauth_extra["raw_info"]["two_factor_authentication"]
end
```

### Identity data

You can also store extra data on the external identities. The most common use case is storing [timestamps](https://github.com/janko/rodauth-omniauth/wiki/Timestamps). You could also persist data about external identities, for example:

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

With this configuration, the identity record will be automatically synced with most recent state on each provider login. If you would like to only save provider data when the identity is created, you can override the insert hash instead:

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

### Identity schema

You can change the table name or any of the column names:

```rb
omniauth_identities_table :account_identities
omniauth_identities_id_column :id
omniauth_identities_account_id_column :account_id
omniauth_identities_provider_column :provider
omniauth_identities_uid_column :uid
```

## Base

The `omniauth` feature builds on top of the `omniauth_base` feature, which sets up OmniAuth and routes its requests, but has no interaction with the database. So, if you would prefer to handle external logins differently, you can load just the `omniauth_base` feature, and implement your own callback phase.

```rb
# in your Rodauth configuration
enable :omniauth_base

omniauth_provider :github, ENV["GITHUB_CLIENT_ID"], ENV["GITHUB_CLIENT_SECRET"], scope: "user"
omniauth_provider :apple, ENV["APPLE_CLIENT_ID"], ENV["APPLE_CLIENT_SECRET"], scope: "email name"
```
```rb
# in your routes
get "/auth/:provider/callback", to: "rodauth#omniauth_login"
```
```rb
class RodauthController < ApplicationController
  def omniauth_login
    # ...
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

### Inheritance

The registered providers are inherited between Rodauth auth classes, so you can have fine-grained configuration for different account types.

```rb
class RodauthBase < Rodauth::Auth
  configure do
    enable :omniauth_base
    omniauth_provider :google_oauth2, ...
  end
end

class RodauthMain < RodauthBase
  configure do
    omniauth_provider :facebook, ...
  end
end

class RodauthAdmin < RodauthBase
  configure do
    omniauth_provider :twitter, ...
    omniauth_provider :github, ...
  end
end
```
```rb
rodauth.omniauth_providers #=> [:google_oauth2, :facebook]
rodauth(:admin).omniauth_providers #=> [:google_oauth2, :twitter, :github]
```

### JSON

JSON requests are supported for request and callback phases. The request phase endpoint will return the authorize URL:

```http
POST /auth/github
Accept: application/json
Content-Type: application/json
```
```http
200 OK
Content-Type: application/json

{ "authorize_url": "https://github.com/login/oauth/authorize?..." }
```

When you redirect the user to the authorize URL, and they authorize the OAuth app, the callback endpoint they're redirected to will contain query parameters that need to be included in the callback request to the backend.

```http
GET /auth/github/callback?code=...&state=...
Accept: application/json
Content-Type: application/json
```
```http
200 OK
Content-Type: application/json

{ "success": "You have been logged in" }
```

> [!NOTE]
> Unless you're using JWT, make sure you're persisting cookies across requests, as most OmniAuth strategies rely on session storage.

If there was an OmniAuth failure, the error type will be included in the response:

```http
500 Internal Server Error
Content-Type: application/json

{ "error_type": "some_error", "error": "There was an error logging in with the external provider" }
```

In this flow, you'll need to configure the callback URL on the OAuth app to point to the frontend app. In the OmniAuth strategy, you'll need to configure the same redirect URL for OAuth requests, but keep the backend callback endpoint. For strategies based on [omniauth-oauth2], you can achieve this as follows:

```rb
omniauth_provider :github, ENV["GITHUB_CLIENT_ID"], ENV["GITHUB_CLIENT_SECRET"],
  authorize_params: { redirect_uri: "https://frontend.example.com/github/callback" },
  token_params: { redirect_uri: "https://frontend.example.com/github/callback" }
```

You can change authorize URL and error type keys:

```rb
omniauth_authorize_url_key "authorize_url"
omniauth_error_type_key "error_type"
```

### JWT

JWT requests are supported for the request and callback phases. OmniAuth data will be stored in the JWT token during the request phase, and restored during the callback phase, as long as the updated JWT token is passed.

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
[rodauth-rails]: https://github.com/janko/rodauth-rails
[omniauth-oauth2]: https://github.com/omniauth/omniauth-oauth2

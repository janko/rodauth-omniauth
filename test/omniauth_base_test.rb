require "test_helper"

describe "Rodauth omniauth_base feature" do
  it "runs registered omniauth strategies" do
    rodauth do
      enable :omniauth_base
      omniauth_provider :developer
    end
    roda do |r|
      r.rodauth

      r.is "auth/developer/callback" do
        rodauth.omniauth_auth.to_json
      end
    end

    omniauth_login "/auth/developer", name: "Janko", email: "janko@hey.com"
    assert_equal "/auth/developer/callback", page.current_path

    auth = JSON.parse(page.html)

    assert_equal "developer",     auth["provider"]
    assert_equal "janko@hey.com", auth["uid"]
    assert_equal "Janko",         auth["info"]["name"]
    assert_equal "janko@hey.com", auth["info"]["email"]
  end

  it "supports passing strategy arguments" do
    rodauth do
      enable :omniauth_base
      omniauth_provider :developer, uid_field: :name
    end
    roda do |r|
      r.rodauth

      r.is "auth/developer/callback" do
        rodauth.omniauth_uid
      end
    end

    omniauth_login "/auth/developer", name: "Janko"
    assert_equal "Janko", page.html
  end

  it "saves omniauth providers" do
    rodauth do
      enable :omniauth_base
      omniauth_provider :developer
    end
    roda do |r|
      r.root { rodauth.omniauth_providers.inspect }
    end

    visit "/"
    assert_equal "[:developer]", page.text
  end

  it "allows setting strategy classes" do
    rodauth do
      enable :omniauth_base
      omniauth_provider OmniAuth::Strategies::Developer, name: :foo
    end
    roda do |r|
      r.rodauth
      r.root { rodauth.omniauth_providers.inspect }
    end

    visit "/"
    assert_equal "[:foo]", page.text

    visit "/auth/foo"
    assert_match "User Info", page.text
  end

  it "allow setting omniauth prefix" do
    rodauth do
      enable :omniauth_base
      omniauth_prefix "/external"
      omniauth_provider :developer
    end
    roda do |r|
      r.rodauth

      r.is "external/developer/callback" do
        rodauth.omniauth_auth['uid']
      end
    end

    visit "/external/developer"
    assert_match "/external/developer/callback", page.html

    omniauth_login name: "Janko", email: "janko@hey.com"
    assert_equal "/external/developer/callback", page.current_path
    assert_equal "janko@hey.com", page.html
  end

  it "nests inside the main prefix" do
    rodauth do
      enable :omniauth_base
      prefix "/user"
      omniauth_prefix "/external"
      omniauth_provider :developer
    end
    roda do |r|
      r.on "user" do
        r.rodauth

        r.is "external/developer/callback" do
          rodauth.omniauth_auth['uid']
        end
      end
    end

    visit "/user/external/developer"
    assert_match "/user/external/developer/callback", page.html

    omniauth_login name: "Janko", email: "janko@hey.com"
    assert_equal "/user/external/developer/callback", page.current_path
    assert_equal "janko@hey.com", page.html
  end

  it "allows disabling autorouting" do
    rodauth do
      enable :omniauth_base
      prefix "/user"
      omniauth_prefix "/auth"
      omniauth_autoroute? false
      omniauth_provider :developer
    end
    roda do |r|
      r.rodauth
      rodauth.route_omniauth!

      r.on "auth/developer/callback" do
        rodauth.omniauth_uid
      end

      r.root { rodauth.omniauth_request_path(:developer) }
    end

    omniauth_login "/auth/developer", name: "Janko", email: "janko@hey.com"

    assert_equal "/auth/developer/callback", page.current_path
    assert_equal "janko@hey.com", page.html

    visit "/"
    assert_equal "/auth/developer", page.html
  end

  it "defines helper methods for omniauth auth data" do
    m = self

    rodauth do
      enable :omniauth_base
      omniauth_provider :developer
    end
    roda do |r|
      r.rodauth

      r.is "auth/developer/callback" do
        m.assert_equal "developer",     rodauth.omniauth_provider
        m.assert_equal "janko@hey.com", rodauth.omniauth_uid
        m.assert_equal "Janko",         rodauth.omniauth_info["name"]
        m.assert_equal Hash.new,        rodauth.omniauth_credentials
        m.assert_equal Hash.new,        rodauth.omniauth_extra

        ""
      end
    end

    omniauth_login "/auth/developer", name: "Janko", email: "janko@hey.com"
  end

  it "defines helper methods for params, strategy, and origin" do
    m = self

    rodauth do
      enable :omniauth_base
      omniauth_provider :developer
    end
    roda do |r|
      r.rodauth

      r.is "auth/developer/callback" do
        m.assert_equal "bar", rodauth.omniauth_params["foo"]
        m.assert_instance_of OmniAuth::Strategies::Developer, rodauth.omniauth_strategy
        m.assert_equal "/foo", rodauth.omniauth_origin

        ""
      end
    end

    omniauth_login "/auth/developer?foo=bar&origin=/foo"
  end

  it "allows handling failure" do
    m = self

    rodauth do
      enable :omniauth_base
      omniauth_provider :developer
      omniauth_before_callback_phase do |provider|
        omniauth_strategy.fail!(:some_error, KeyError.new("foo"))
      end
      omniauth_on_failure do |provider|
        m.assert_equal :some_error, omniauth_error_type
        m.assert_instance_of KeyError, omniauth_error
        m.assert_equal "foo", omniauth_error.message
        m.assert_instance_of OmniAuth::Strategies::Developer, omniauth_error_strategy

        redirect "/auth/failure"
      end
    end
    roda do |r|
      r.rodauth

      r.get "auth/failure" do
        "custom failure response"
      end
    end

    omniauth_login "/auth/developer"
    assert_equal "custom failure response", page.html
  end

  it "defines path and url methods for request and callback routes" do
    m = self

    rodauth do
      enable :omniauth_base
      omniauth_provider :developer
    end
    roda do |r|
      r.root do
        m.assert_equal "/auth/developer",                               rodauth.omniauth_request_path(:developer)
        m.assert_equal "/auth/developer?foo=bar",                       rodauth.omniauth_request_path(:developer, foo: "bar")
        m.assert_equal "http://www.example.com/auth/developer",         rodauth.omniauth_request_url(:developer)
        m.assert_equal "http://www.example.com/auth/developer?foo=bar", rodauth.omniauth_request_url(:developer, foo: "bar")

        m.assert_equal "/auth/developer/callback",                               rodauth.omniauth_callback_path(:developer)
        m.assert_equal "/auth/developer/callback?foo=bar",                       rodauth.omniauth_callback_path(:developer, foo: "bar")
        m.assert_equal "http://www.example.com/auth/developer/callback",         rodauth.omniauth_callback_url(:developer)
        m.assert_equal "http://www.example.com/auth/developer/callback?foo=bar", rodauth.omniauth_callback_url(:developer, foo: "bar")

        ""
      end
    end

    visit "/"
  end

  it "sets path and url according to omniauth prefix" do
    m = self

    rodauth do
      enable :omniauth_base
      omniauth_prefix "/other"
      omniauth_provider :developer
    end
    roda do |r|
      r.root do
        m.assert_equal "/other/developer",                       rodauth.omniauth_request_path(:developer)
        m.assert_equal "http://www.example.com/other/developer", rodauth.omniauth_request_url(:developer)

        m.assert_equal "/other/developer/callback",                       rodauth.omniauth_callback_path(:developer)
        m.assert_equal "http://www.example.com/other/developer/callback", rodauth.omniauth_callback_url(:developer)

        ""
      end
    end

    visit "/"
  end

  it "supports strategy setup" do
    rodauth do
      enable :omniauth_base
      omniauth_provider :developer
      omniauth_setup do |provider|
        omniauth_strategy.options[:uid_field] = :name
      end
    end
    roda do |r|
      r.rodauth

      r.is "auth/developer/callback" do
        rodauth.omniauth_uid
      end
    end

    omniauth_login "/auth/developer", name: "Janko"
    assert_equal "Janko", page.html
  end

  it "supports before request and callback phase hooks" do
    rodauth do
      enable :omniauth_base
      omniauth_provider :developer, name: :one
      omniauth_provider :developer, name: :two
      omniauth_before_request_phase { |provider| session["request_hook"] = provider }
      omniauth_before_callback_phase { |provider| session["callback_hook"] = provider }
    end
    roda do |r|
      r.rodauth

      r.is "auth", ["one", "two"], "callback" do
        [session["request_hook"], session["callback_hook"]].join(",")
      end
    end

    omniauth_login "/auth/one"
    assert_equal "one,one", page.html

    omniauth_login "/auth/two"
    assert_equal "two,two", page.html
  end

  it "supports requiring request phase to be POST" do
    OmniAuth.config.allowed_request_methods = %i[post]

    rodauth do
      enable :omniauth_base
      omniauth_provider :developer
      omniauth_on_failure do |provider|
        response.write "#{omniauth_error.class}: #{omniauth_error.message}"
        request.halt
      end
    end
    roda do |r|
      r.rodauth

      r.root do
        <<~HTML
          <form action="#{rodauth.omniauth_request_path(:developer)}" method="post">
            #{rodauth.csrf_tag(rodauth.omniauth_request_path(:developer))}
            <input type="submit" value="Request"/>
          </form>
        HTML
      end
    end

    visit "/auth/developer"
    assert_equal 404, page.status_code

    visit "/"
    click_on "Request"
    assert_equal "/auth/developer", page.current_path
    assert_match "User Info", page.html

    page.driver.post "/auth/developer"
    assert_equal "Roda::RodaPlugins::RouteCsrf::InvalidToken: encoded token is not a string", page.html

    OmniAuth.config.allowed_request_methods = %i[get post]
  end

  it "works with sessions roda plugin" do
    rodauth do
      enable :omniauth_base
      omniauth_provider :developer
    end
    roda do |r|
      r.rodauth

      r.is "auth/developer/callback" do
        request.env["omniauth.params"].to_json
      end
    end

    omniauth_login "/auth/developer?foo=bar"
    assert_equal '{"foo":"bar"}', page.html
  end
end

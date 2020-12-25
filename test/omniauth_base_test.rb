require "test_helper"

describe "Rodauth omniauth_base feature" do
  it "runs registered omniauth strategies" do
    rodauth do
      enable :omniauth_base
      omniauth_provider :developer
    end
    roda do |r|
      r.on "auth" do
        r.omniauth

        r.is "developer/callback" do
          rodauth.omniauth_auth.to_json
        end
      end
    end

    visit "/auth/developer"
    login(name: "Janko", email: "janko@hey.com")
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
      r.on "auth" do
        r.omniauth

        r.is "developer/callback" do
          rodauth.omniauth_uid
        end
      end
    end

    visit "/auth/developer"
    login(name: "Janko")

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

  it "allows mapping omniauth strategies" do
    rodauth do
      enable :omniauth_base
      omniauth_strategies(
        :foo => :developer,
        :bar => OmniAuth::Strategies::Developer,
        :baz => "OmniAuth::Strategies::Developer",
      )
      omniauth_provider :foo
      omniauth_provider :bar
      omniauth_provider :baz
    end
    roda do |r|
      r.on("auth") { r.omniauth }
      r.root { rodauth.omniauth_providers.inspect }
    end

    visit "/"
    assert_equal "[:foo, :bar, :baz]", page.text

    visit "/auth/foo"
    assert_match "User Info", page.html

    visit "/auth/bar"
    assert_match "User Info", page.html

    visit "/auth/baz"
    assert_match "User Info", page.html
  end

  it "resolves omniauth strategies on configure" do
    rodauth do
      enable :omniauth_base
      omniauth_provider :undefined
    end
    assert_raises LoadError do
      roda do |r|
      end
    end
  end

  it "allow setting omniauth prefix" do
    rodauth do
      enable :omniauth_base
      omniauth_prefix "/other"
      omniauth_provider :developer
    end
    roda do |r|
      r.on("other") { r.omniauth }
    end

    visit "/other/developer"
    assert_match "/other/developer/callback", page.html
  end

  it "defaults omniauth prefix to prefix if set" do
    rodauth do
      enable :omniauth_base
      prefix "/other"
      omniauth_provider :developer
    end
    roda do |r|
      r.on("other") { r.omniauth }
    end

    visit "/other/developer"
    assert_match "/other/developer/callback", page.html
  end

  it "defines helper methods for omniauth auth data" do
    m = self

    rodauth do
      enable :omniauth_base
      omniauth_provider :developer
    end
    roda do |r|
      r.on "auth" do
        r.omniauth

        r.is "developer/callback" do
          m.assert_equal :developer,      rodauth.omniauth_provider
          m.assert_equal "janko@hey.com", rodauth.omniauth_uid
          m.assert_equal "Janko",         rodauth.omniauth_info["name"]
          m.assert_equal Hash.new,        rodauth.omniauth_credentials
          m.assert_equal Hash.new,        rodauth.omniauth_extra

          ""
        end
      end
    end

    visit "/auth/developer"
    login(name: "Janko", email: "janko@hey.com")
  end

  it "defines helper methods for params, strategy, and origin" do
    m = self

    rodauth do
      enable :omniauth_base
      omniauth_provider :developer
    end
    roda do |r|
      r.on "auth" do
        r.omniauth

        r.is "developer/callback" do
          m.assert_equal "bar", rodauth.omniauth_params["foo"]
          m.assert_instance_of OmniAuth::Strategies::Developer, rodauth.omniauth_strategy
          m.assert_equal "/foo", rodauth.omniauth_origin

          ""
        end
      end
    end

    visit "/auth/developer?foo=bar&origin=/foo"
    login
  end

  it "allows handling failure" do
    m = self

    rodauth do
      enable :omniauth_base
      omniauth_provider :developer
      before_omniauth_callback_phase do |provider|
        omniauth_strategy.fail!(:some_error, KeyError.new("foo"))
      end
      handle_omniauth_failure do |provider|
        m.assert_equal :some_error, omniauth_error_type
        m.assert_instance_of KeyError, omniauth_error
        m.assert_equal "foo", omniauth_error.message
        m.assert_instance_of OmniAuth::Strategies::Developer, omniauth_error_strategy

        redirect "/auth/failure"
      end
    end
    roda do |r|
      r.on "auth" do
        r.omniauth

        r.get "failure" do
          "custom failure response"
        end
      end
    end

    visit "/auth/developer"
    login

    assert_equal "custom failure response", page.html
  end

  it "defines path, and url methods for request and callback routes" do
    m = self

    rodauth do
      enable :omniauth_base
      omniauth_provider :developer
    end
    roda do |r|
      r.root do
        m.assert_equal "developer",                                     rodauth.omniauth_request_route(:developer)
        m.assert_equal "/auth/developer",                               rodauth.omniauth_request_path(:developer)
        m.assert_equal "/auth/developer?foo=bar",                       rodauth.omniauth_request_path(:developer, foo: "bar")
        m.assert_equal "http://www.example.com/auth/developer",         rodauth.omniauth_request_url(:developer)
        m.assert_equal "http://www.example.com/auth/developer?foo=bar", rodauth.omniauth_request_url(:developer, foo: "bar")

        m.assert_equal "developer/callback",                                     rodauth.omniauth_callback_route(:developer)
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

  it "raises exception in unregistered provider name" do
    m = self

    rodauth do
      enable :omniauth_base
      omniauth_provider :developer
    end
    roda do |r|
      r.root do
        m.assert_raises(ArgumentError) { rodauth.omniauth_request_path(:unknown) }
        m.assert_raises(ArgumentError) { rodauth.omniauth_request_url(:unknown) }
        m.assert_raises(ArgumentError) { rodauth.omniauth_callback_path(:unknown) }
        m.assert_raises(ArgumentError) { rodauth.omniauth_callback_url(:unknown) }

        ""
      end
    end

    visit "/"
  end

  it "sets route, path and url according to omniauth provider name" do
    m = self

    rodauth do
      enable :omniauth_base
      omniauth_strategies :test => :developer
      omniauth_provider :test
    end
    roda do |r|
      r.root do
        m.assert_equal "test",                              rodauth.omniauth_request_route(:test)
        m.assert_equal "/auth/test",                        rodauth.omniauth_request_path(:test)
        m.assert_equal "http://www.example.com/auth/test", rodauth.omniauth_request_url(:test)

        m.assert_equal "test/callback",                              rodauth.omniauth_callback_route(:test)
        m.assert_equal "/auth/test/callback",                        rodauth.omniauth_callback_path(:test)
        m.assert_equal "http://www.example.com/auth/test/callback", rodauth.omniauth_callback_url(:test)

        m.assert_raises(ArgumentError) { rodauth.omniauth_request_path(:developer) }
        m.assert_raises(ArgumentError) { rodauth.omniauth_request_url(:developer) }
        m.assert_raises(ArgumentError) { rodauth.omniauth_callback_path(:developer) }
        m.assert_raises(ArgumentError) { rodauth.omniauth_callback_url(:developer) }

        ""
      end
    end

    visit "/"
  end

  it "supports overriding request and callback routes" do
    m = self

    rodauth do
      enable :omniauth_base
      omniauth_prefix "/other"
      omniauth_provider :developer
      omniauth_request_route { |provider| "#{provider}/request" }
      omniauth_callback_route { |provider| "#{provider}/back" }
    end
    roda do |r|
      r.on "auth" do
        r.omniauth
        r.is("developer/back") { "" }
      end

      r.root do
        m.assert_equal "/other/developer/request",                       rodauth.omniauth_request_path(:developer)
        m.assert_equal "http://www.example.com/other/developer/request", rodauth.omniauth_request_url(:developer)

        m.assert_equal "/other/developer/back",                       rodauth.omniauth_callback_path(:developer)
        m.assert_equal "http://www.example.com/other/developer/back", rodauth.omniauth_callback_url(:developer)

        ""
      end
    end

    visit "/"

    visit "/auth/developer/request"
    login
    assert_equal "/auth/developer/back", page.current_path
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
      r.on "auth" do
        r.omniauth

        r.is "developer/callback" do
          rodauth.omniauth_uid
        end
      end
    end

    visit "/auth/developer"
    login(name: "Janko")

    assert_equal "Janko", page.html
  end

  it "supports hooks before request and callback phases" do
    rodauth do
      enable :omniauth_base
      omniauth_strategies :one => :developer, :two => :developer
      omniauth_provider :one
      omniauth_provider :two
      before_omniauth_request_phase { |provider| session[:request_hook] = provider }
      before_omniauth_callback_phase { |provider| session[:callback_hook] = provider }
    end
    roda do |r|
      r.on "auth" do
        r.omniauth

        r.is String, "callback" do
          [session[:request_hook], session[:callback_hook]].join(",")
        end
      end
    end

    visit "/auth/one"
    login
    assert_equal "one,one", page.html

    visit "/auth/two"
    login
    assert_equal "two,two", page.html
  end

  it "supports requiring request phase to be POST" do
    rodauth do
      enable :omniauth_base
      omniauth_provider :developer
      omniauth_request_phase_only_post? true
    end
    roda do |r|
      r.on "auth" do
        r.omniauth
      end

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
    assert_equal 405, page.status_code
    assert_equal "POST", page.response_headers["Allow"]

    visit "/"
    click_on "Request"
    assert_equal "/auth/developer", page.current_path
    assert_match "User Info", page.html

    assert_raises Roda::RodaPlugins::RouteCsrf::InvalidToken do
      page.driver.post "/auth/developer"
    end
  end
end

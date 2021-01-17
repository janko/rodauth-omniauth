# frozen_string_literal: true

require "omniauth"
require "omniauth/version"

module Rodauth
  Feature.define(:omniauth_base, :OmniauthBase) do
    error_flash "There was an error logging in with the external provider", :omniauth_failure

    redirect(:omniauth_failure)

    auth_value_method :omniauth_prefix, OmniAuth.config.path_prefix
    auth_value_method :omniauth_strategies, {}
    auth_value_method :omniauth_failure_error_status, 500

    auth_methods(
      :omniauth_before_request_phase,
      :omniauth_before_callback_phase,
      :omniauth_callback_route,
      :omniauth_on_failure,
      :omniauth_request_route,
      :omniauth_request_validation_phase,
      :omniauth_setup,
    )

    configuration_module_eval do
      def omniauth_provider(provider, *args, **options)
        @auth.omniauth_providers[provider] = [*args, **options]
      end
    end

    def self.included(auth)
      auth.singleton_class.send(:attr_accessor, :omniauth_providers)
      auth.omniauth_providers = {}
    end

    def post_configure
      super

      # ensure upfront that all registered providers can be resolved
      omniauth_providers.each { |provider| omniauth_strategy_class(provider) }

      self.class.roda_class.plugin :run_handler
      self.class.roda_class.plugin :rodauth_omniauth

      OmniAuth.config.request_validation_phase = -> (env) do
        env["omniauth.rodauth"].send(:omniauth_request_validation_phase, env["omniauth.strategy"].name)
      end if omniauth_2?
      OmniAuth.config.before_request_phase = -> (env) do
        env["omniauth.rodauth"].send(:omniauth_before_request_phase, env["omniauth.strategy"].name)
      end
      OmniAuth.config.before_callback_phase = -> (env) do
        env["omniauth.rodauth"].send(:omniauth_before_callback_phase, env["omniauth.strategy"].name)
      end
      OmniAuth.config.on_failure = -> (env) do
        env["omniauth.rodauth"].send(:omniauth_on_failure, env["omniauth.error.strategy"].name)
      end
    end

    def route_omniauth!
      omniauth_run omniauth_app
    end

    %w[provider uid info credentials extra].each do |auth_key|
      define_method(:"omniauth_#{auth_key}") do
        omniauth_auth.fetch(auth_key)
      end
    end

    %w[auth params strategy origin error error_type error_strategy].each do |data|
      define_method(:"omniauth_#{data}") do
        request.env.fetch("omniauth.#{data.tr("_", ".")}")
      end
    end

    def omniauth_email
      omniauth_info.fetch("email")
    end

    [:request, :callback].each do |phase|
      define_method(:"omniauth_#{phase}_path") do |provider, params = {}|
        unless omniauth_providers.include?(provider.to_sym)
          fail ArgumentError, "unregistered omniauth provider: #{provider}"
        end

        path  = "#{omniauth_prefix}/#{send(:"omniauth_#{phase}_route", provider)}"
        path += "?#{Rack::Utils.build_nested_query(params)}" unless params.empty?
        path
      end

      define_method(:"omniauth_#{phase}_url") do |provider, params = {}|
        "#{base_url}#{send(:"omniauth_#{phase}_path", provider, params)}"
      end
    end

    def omniauth_request_route(provider)
      "#{provider}"
    end

    def omniauth_callback_route(provider)
      "#{provider}/callback"
    end

    def omniauth_providers
      self.class.omniauth_providers.keys
    end

    private

    def omniauth_run(app)
      session # set "rack.session" when roda sessions plugin is used
      request.env["omniauth.rodauth"] = self
      request.run app, not_found: :pass do |res|
        handle_omniauth_response(res)
      end
    ensure
      request.env.delete("omniauth.rodauth")
    end

    # returns rack app with all registered strategies added to the middleware stack
    def omniauth_app
      app = Rack::Builder.new
      omniauth_providers.each do |provider|
        app.use omniauth_strategy_class(provider), *omniauth_strategy_args(provider)
      end
      app.run -> (env) { [404, {}, []] } # pass through
      app
    end

    def omniauth_request_validation_phase(provider)
      check_csrf if check_csrf?
    end

    def omniauth_before_request_phase(provider)
      # can be overrridden to perform code before request phase
    end

    def omniauth_before_callback_phase(provider)
      # can be overrridden to perform code before callback phase
    end

    def omniauth_setup(provider)
      # can be overridden to setup the strategy
    end

    def omniauth_on_failure(provider)
      set_redirect_error_status omniauth_failure_error_status
      set_redirect_error_flash omniauth_failure_error_flash
      redirect omniauth_failure_redirect
    end

    def handle_omniauth_response(res)
      # overridden in omniauth_jwt feature
    end

    def omniauth_strategy_args(provider)
      *args, options = omniauth_provider_args(provider)

      our_options = {
        name:          provider,
        request_path:  "#{omniauth_prefix if omniauth_2?}/#{omniauth_request_route(provider)}",
        callback_path: "#{omniauth_prefix if omniauth_2?}/#{omniauth_callback_route(provider)}",
        setup:         -> (env) { omniauth_setup(provider) },
      }

      [*args, options.merge(our_options)]
    end

    def omniauth_provider_args(provider)
      self.class.omniauth_providers.fetch(provider)
    end

    def omniauth_strategy_class(provider)
      strategy = omniauth_strategies[provider] || provider

      case strategy
      when Symbol then omniauth_resolve_strategy(strategy)
      when String then Object.const_get(strategy)
      when Class  then strategy
      else
        fail ArgumentError, "provider must be a Symbol, String or a Class, got #{provider.inspect}"
      end
    end

    # Uses the logic OmniAuth uses to resolve strategies from symbols.
    def omniauth_resolve_strategy(provider)
      OmniAuth::Strategies.const_get(OmniAuth::Utils.camelize(provider.to_s).to_s)
    rescue NameError
      fail LoadError, "Could not find matching strategy for #{provider.inspect}. You may need to install an additional gem (such as omniauth-#{provider})."
    end

    def omniauth_2?
      Gem::Version.new(OmniAuth::VERSION) >= Gem::Version.new("2.0")
    end
  end
end

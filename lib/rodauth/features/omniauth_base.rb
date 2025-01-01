# frozen_string_literal: true

require "omniauth"

module Rodauth
  Feature.define(:omniauth_base, :OmniauthBase) do
    error_flash "There was an error logging in with the external provider", :omniauth_failure

    redirect :omniauth_failure

    auth_value_method :omniauth_prefix, OmniAuth.config.path_prefix
    auth_value_method :omniauth_failure_error_status, 500

    auth_value_method :omniauth_authorize_url_key, "authorize_url"
    auth_value_method :omniauth_error_type_key, "error_type"

    auth_methods(
      :build_omniauth_app,
      :omniauth_before_callback_phase,
      :omniauth_before_request_phase,
      :omniauth_on_failure,
      :omniauth_request_validation_phase,
      :omniauth_setup,
    )

    configuration_module_eval do
      def omniauth_provider(provider, *args)
        @auth.instance_exec { @omniauth_providers << [provider, *args] }
      end
    end

    def post_configure
      super

      omniauth_app = build_omniauth_app.to_app
      self.class.send(:define_method, :omniauth_app) { omniauth_app }

      self.class.roda_class.plugin :run_handler

      i18n_register File.expand_path("#{__dir__}/../../../locales") if features.include?(:i18n)
    end

    def route!
      super
      route_omniauth!
    end

    def route_omniauth!
      omniauth_run omniauth_app
      nil
    end

    { request: "", callback: "/callback" }.each do |phase, suffix|
      define_method(:"omniauth_#{phase}_url") do |provider, params = {}|
        route_url(send(:"omniauth_#{phase}_route", provider), params)
      end

      define_method(:"omniauth_#{phase}_path") do |provider, params = {}|
        route_path(send(:"omniauth_#{phase}_route", provider), params)
      end

      define_method(:"omniauth_#{phase}_route") do |provider|
        "#{omniauth_prefix[1..-1]}/#{provider}#{suffix}"
      end
    end

    %w[email name].each do |info_key|
      define_method(:"omniauth_#{info_key}") do
        omniauth_info[info_key] if omniauth_info
      end
    end

    %w[provider uid info credentials extra].each do |auth_key|
      define_method(:"omniauth_#{auth_key}") do
        omniauth_auth[auth_key] if omniauth_auth
      end
    end

    %w[auth params strategy origin error error_type error_strategy].each do |data|
      define_method(:"omniauth_#{data}") do
        request.env["omniauth.#{data.tr("_", ".")}"]
      end
    end

    def omniauth_providers
      self.class.instance_variable_get(:@omniauth_providers).map do |(provider, *args)|
        options = args.last.is_a?(Hash) ? args.last : {}
        options[:name] || provider
      end
    end

    private

    def omniauth_run(app)
      omniauth_around_run do
        request.run app, not_found: :pass do |res|
          handle_omniauth_response(res)
        end
      end
    end

    # returns rack app with all registered strategies added to the middleware stack
    def build_omniauth_app
      builder = OmniAuth::Builder.new
      builder.options(
        path_prefix: omniauth_prefix,
        setup: -> (env) { env["rodauth.omniauth.instance"].send(:omniauth_setup) }
      )
      builder.configure do |config|
        [:request_validation_phase, :before_request_phase, :before_callback_phase, :on_failure].each do |hook|
          config.send(:"#{hook}=", -> (env) { env["rodauth.omniauth.instance"].send(:"omniauth_#{hook}") })
        end
      end
      self.class.instance_variable_get(:@omniauth_providers).each do |(provider, *args)|
        options = args.pop if args.last.is_a?(Hash)
        builder.provider provider, *args, **(options || {})
      end
      builder.run -> (env) { [404, {}, []] } # pass through
      builder
    end

    def omniauth_request_validation_phase
      check_csrf if check_csrf?
    end

    def omniauth_before_request_phase
      # can be overrridden to perform code before request phase
    end

    def omniauth_before_callback_phase
      # can be overrridden to perform code before callback phase
    end

    def omniauth_setup
      # can be overridden to setup the strategy
    end

    def omniauth_on_failure
      if features.include?(:json) && use_json?
        json_response[omniauth_error_type_key] = omniauth_error_type
      end

      set_response_error_reason_status(:omniauth_failure, omniauth_failure_error_status)
      set_redirect_error_flash omniauth_failure_error_flash
      redirect omniauth_failure_redirect
    end

    def omniauth_around_run
      set_omniauth_rodauth do
        set_omniauth_session do
          yield
        end
      end
    end

    # Ensures the OmniAuth app uses the same session as Rodauth.
    def set_omniauth_session(&block)
      if features.include?(:jwt) && use_jwt?
        set_omniauth_jwt_session(&block)
      else
        session # ensure "rack.session" is set when roda sessions plugin is used
        yield
      end
    end

    # Makes OmniAuth strategies use the JWT session hash.
    def set_omniauth_jwt_session
      rack_session = request.env["rack.session"]
      session.transform_keys!(&:to_s) unless scope.opts[:sessions_convert_symbols]
      request.env["rack.session"] = session
      yield
    ensure
      session.transform_keys!(&:to_sym) unless scope.opts[:sessions_convert_symbols]
      request.env.delete("rack.session")
      request.env["rack.session"] = rack_session if rack_session
    end

    # Makes the Rodauth instance accessible inside OmniAuth strategies
    # and callbacks.
    def set_omniauth_rodauth
      request.env["rodauth.omniauth.instance"] = self
      yield
    ensure
      request.env.delete("rodauth.omniauth.instance")
    end

    # Returns authorization URL when using the JSON feature.
    def handle_omniauth_response(res)
      return unless features.include?(:json) && use_json?

      if res[0] == 302
        json_response[omniauth_authorize_url_key] = res[1]["Location"]
        return_json_response
      end
    end

    def self.included(auth)
      auth.extend OmniauthBase::ClassMethods
      auth.instance_variable_set(:@omniauth_providers, [])
    end
  end

  module OmniauthBase
    module ClassMethods
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@omniauth_providers, @omniauth_providers.clone)
      end

      def freeze
        super
        @omniauth_providers.freeze
      end
    end
  end
end

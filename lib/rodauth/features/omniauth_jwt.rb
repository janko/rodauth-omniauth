# frozen_string_literal: true

module Rodauth
  Feature.define(:omniauth_jwt, :OmniauthJwt) do
    depends :omniauth_base, :jwt

    auth_value_method :omniauth_jwt_authorize_url_key, "authorize_url"
    auth_value_method :omniauth_jwt_error_type_key, "error_type"

    def omniauth_run
      return super unless use_jwt?

      with_omniauth_jwt_session { super }
    end

    private

    def handle_omniauth_response((status, headers, body))
      return super unless use_jwt?

      if status == 302
        json_response[omniauth_jwt_authorize_url_key] = headers["Location"]
        return_json_response
      end
    end

    def with_omniauth_jwt_session
      original_session = request.env["rack.session"]
      request.env["rack.session"] = session
      yield
    ensure
      request.env["rack.session"] = original_session
    end

    def handle_omniauth_failure(provider)
      json_response[omniauth_jwt_error_type_key] = omniauth_error_type
      super
    end
  end
end

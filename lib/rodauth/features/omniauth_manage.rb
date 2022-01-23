# frozen_string_literal: true

module Rodauth
  Feature.define(:omniauth_manage, :OmniauthManage) do
    loaded_templates %w[omniauth-manage omniauth-remove]
    view "omniauth-manage", "Manage External Identities", :omniauth_manage
    view "omniauth-remove", "Disconnect External Identity", :omniauth_remove

    additional_form_tags :omniauth_remove

    before :omniauth_remove
    after :omniauth_remove

    notice_flash "The external identity has been connected to your account", :omniauth_connected
    notice_flash "The external identity has been disconnected from your account", :omniauth_remove
    error_flash "There was an error disconnecting the external identity", :omniauth_remove

    redirect(:omniauth_connected)
    redirect(:omniauth_remove)

    auth_value_method :omniauth_provider_param, "provider"

    auth_value_methods(
      :omniauth_removal_requires_password?,
    )

    auth_cached_method :omniauth_add_links
    auth_cached_method :omniauth_remove_links
    auth_cached_method :omniauth_login_links

    route(:omniauth_manage) do |r|
      require_account
      before_omniauth_manage_route

      r.get do
        omniauth_manage_view
      end
    end

    route(:omniauth_add) do |r|
      require_account
    end

    route(:omniauth_remove) do |r|
      require_account
      before_omniauth_remove_route

      r.get do
        omniauth_remove_view
      end

      r.post do
        provider = param(omniauth_provider_param)

        catch_error do
          if omniauth_removal_requires_password? && !password_match?(param(password_param))
            throw_error_status(invalid_password_error_status, password_param, invalid_password_message)
          end

          transaction do
            before_omniauth_remove
            omniauth_remove(provider)
            after_omniauth_remove
          end

          set_notice_flash omniauth_remove_notice_flash
          redirect omniauth_remove_redirect
        end

        set_error_flash omniauth_remove_error_flash
        omniauth_remove_view
      end
    end

    def omniauth_removal_requires_password?
      modifications_require_password?
    end

    private

    def _omniauth_add_links
      (omniauth_providers - omniauth_connected_providers).map do |provider|
        [omniauth_request_path(provider), "Connect #{provider.capitalize}"]
      end
    end

    def _omniauth_remove_links
      omniauth_connected_providers.map do |provider|
        [omniauth_remove_path(provider), "Disconnect #{provider.capitalize}"]
      end
    end

    def _login_form_footer_links
      super + omniauth_login_links
    end

    def _omniauth_login_links
      omniauth_providers.map do |provider|
        [10, omniauth_request_path(provider), "Login via #{provider.capitalize}"]
      end
    end
  end
end

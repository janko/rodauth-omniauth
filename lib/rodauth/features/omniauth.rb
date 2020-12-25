# frozen_string_literal: true

require "omniauth"

module Rodauth
  Feature.define(:omniauth, :Omniauth) do
    depends :omniauth_base, :login

    notice_flash "The external identity has been connected to your account", :omniauth_connected
    error_flash "There was an error logging in with the external provider", :omniauth_failure

    redirect(:omniauth_connected)
    redirect(:omniauth_failure)

    auth_value_method :omniauth_identities_table, :account_identities
    auth_value_method :omniauth_identities_id_column, :id
    auth_value_method :omniauth_identities_account_id_column, :account_id
    auth_value_method :omniauth_identities_provider_column, :provider
    auth_value_method :omniauth_identities_uid_column, :uid
    auth_value_method :omniauth_identities_info_column, :info
    auth_value_method :omniauth_identities_credentials_column, :credentials
    auth_value_method :omniauth_identities_extra_column, :extra

    auth_value_method :omniauth_failure_error_status, 500

    auth_methods(
      :omniauth_create_account,
      :before_omniauth_callback_route,
      :get_omniauth_identities,
      :create_omniauth_identity,
      :omniauth_identity_insert_hash,
      :remove_omniauth_identities,
      :serialize_omniauth_data,
      :update_omniauth_identity,
      :omniauth_identity_update_hash,
    )

    auth_cached_method :omniauth_add_links
    auth_cached_method :omniauth_remove_links
    auth_cached_method :omniauth_login_links

    auth_private_methods(
      :retrieve_omniauth_identity,
      :account_from_omniauth_identity,
    )

    route(:omniauth_manage) do
      require_account
      before_omniauth_manage_route

      r.get do
        omniauth_manage_view
      end
    end

    def route_omniauth!
      super

      omniauth_providers.each do |provider|
        handle_omniauth_callback(provider)
      end
    end

    def handle_omniauth_callback(provider)
      request.is omniauth_callback_route(provider) do
        before_omniauth_callback_route(provider)
        account_from_session if logged_in?

        retrieve_omniauth_identity

        if omniauth_identity && !account
          account_from_omniauth_identity
        end

        unless account
          account_from_login(omniauth_info.fetch("email"))
        end

        if account && !open_account?
          set_redirect_error_status(unopen_account_error_status)
          set_redirect_error_flash "#{login_error_flash} (#{unverified_account_message})"
          redirect omniauth_failure_redirect
        end

        transaction do
          unless account
            omniauth_create_account
          end

          if omniauth_identity
            update_omniauth_identity
          else
            create_omniauth_identity
          end
        end

        if logged_in?
          set_notice_flash omniauth_connected_notice_flash
          redirect omniauth_connected_redirect
        end

        login("omniauth")
      end
    end

    def retrieve_omniauth_identity
      @omniauth_identity = _retrieve_omniauth_identity(omniauth_provider, omniauth_uid)
    end

    def account_from_omniauth_identity
      @account = _account_from_omniauth_identity
    end

    def get_omniauth_identities
      omniauth_account_identities_ds.all
    end

    def omniauth_connected_providers
      omniauth_account_identities_ds
        .select_map(omniauth_identities_provider_column)
        .map(&:to_sym)
    end

    def remove_omniauth_identities
      omniauth_account_identities_ds.delete
    end

    def possible_authentication_methods
      methods = super
      methods << "omniauth" if !methods.include?("password") && omniauth_connected_providers.any?
      methods
    end

    private

    attr_reader :omniauth_identity

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
        [5, omniauth_request_path(provider), "Login via #{provider.capitalize}"]
      end
    end

    def omniauth_create_account
      @account = { login_column => omniauth_info.fetch("email") }
      @account[account_id_column] = db[accounts_table].insert(@account)
    end

    def create_omniauth_identity
      omniauth_account_identities_ds.insert(omniauth_identity_insert_hash)
    end

    def update_omniauth_identity(identity_id = omniauth_identity_id)
      omniauth_identities_ds
        .where(omniauth_identities_id_column => identity_id)
        .update(
          omniauth_identities_account_id_column => account_id,
          **omniauth_identity_update_hash
        )
    end

    def handle_omniauth_failure(provider)
      set_redirect_error_status omniauth_failure_error_status
      set_redirect_error_flash omniauth_failure_error_flash
      redirect omniauth_failure_redirect
    end

    def omniauth_identity_insert_hash
      {
        omniauth_identities_account_id_column => account_id,
        omniauth_identities_provider_column => omniauth_provider.to_s,
        omniauth_identities_uid_column => omniauth_uid,
        omniauth_identities_info_column => serialize_omniauth_data(omniauth_info),
        omniauth_identities_credentials_column => serialize_omniauth_data(omniauth_credentials),
        omniauth_identities_extra_column => serialize_omniauth_data(omniauth_extra),
      }
    end

    def omniauth_identity_update_hash
      {
        omniauth_identities_info_column => serialize_omniauth_data(omniauth_info),
        omniauth_identities_credentials_column => serialize_omniauth_data(omniauth_credentials),
        omniauth_identities_extra_column => serialize_omniauth_data(omniauth_extra),
      }
    end

    def _retrieve_omniauth_identity(provider, uid)
      omniauth_identities_ds
        .where(
          omniauth_identities_provider_column => provider.to_s,
          omniauth_identities_uid_column => uid,
        )
        .first
    end

    def _account_from_omniauth_identity
      account_ds(omniauth_identity_account_id).first
    end

    def after_close_account
      super if defined?(super)
      remove_omniauth_identities
    end

    def omniauth_identity_id
      omniauth_identity[omniauth_identities_id_column]
    end

    def omniauth_identity_account_id
      omniauth_identity[omniauth_identities_account_id_column]
    end

    def omniauth_account_identities_ds(acct_id = nil)
      acct_id ||= account ? account_id : session_value

      omniauth_identities_ds.where(omniauth_identities_account_id_column => acct_id)
    end

    def omniauth_identities_ds
      db[omniauth_identities_table]
    end

    def before_omniauth_callback_route(provider)
      # can be overridden to perform code before the callback handler
    end

    def serialize_omniauth_data(data)
      data.to_json
    end

    def template_path(page)
      path = "#{__dir__}/../../../templates/#{page}.str"
      File.exist?(path) ? path : super
    end
  end
end

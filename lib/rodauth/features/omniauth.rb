# frozen_string_literal: true

require "omniauth"

module Rodauth
  Feature.define(:omniauth, :Omniauth) do
    depends :omniauth_base, :login

    before :omniauth_callback_route
    before :omniauth_create_account
    after :omniauth_create_account

    error_flash "The account matching the external identity is currently awaiting verification", :omniauth_login_unverified_account
    error_flash "There is no existing account matching the external identity", :omniauth_login_no_matching_account

    redirect(:omniauth_login_failure) { require_login_redirect }

    auth_value_method :omniauth_identities_table, :account_identities
    auth_value_method :omniauth_identities_id_column, :id
    auth_value_method :omniauth_identities_account_id_column, :account_id
    auth_value_method :omniauth_identities_provider_column, :provider
    auth_value_method :omniauth_identities_uid_column, :uid
    auth_value_method :omniauth_two_factors?, false

    auth_value_methods(
      :omniauth_verify_account?,
      :omniauth_create_account?,
    )

    auth_methods(
      :create_omniauth_identity,
      :omniauth_identity_insert_hash,
      :omniauth_identity_update_hash,
      :remove_omniauth_identities,
      :update_omniauth_identity,
      :omniauth_save_account,
    )

    auth_private_methods(
      :retrieve_omniauth_identity,
      :account_from_omniauth,
      :account_from_omniauth_identity,
      :omniauth_new_account,
    )

    def route_omniauth!
      result = super
      handle_omniauth_callback if omniauth_strategy&.on_callback_path?
      result
    end

    def handle_omniauth_callback
      request.is omniauth_callback_route(omniauth_provider) do
        _handle_omniauth_callback
      end
    end

    def _handle_omniauth_callback
      before_omniauth_callback_route

      unless account
        if omniauth_identity
          account_from_omniauth_identity
        else
          account_from_omniauth
        end
      end

      if account && !open_account?
        if omniauth_verify_account?
          omniauth_verify_account
        else
          set_response_error_reason_status(:unverified_account, unopen_account_error_status)
          set_redirect_error_flash omniauth_login_unverified_account_error_flash
          redirect omniauth_login_failure_redirect
        end
      end

      transaction do
        if !account
          if omniauth_create_account?
            omniauth_create_account
          else
            set_redirect_error_flash omniauth_login_no_matching_account_error_flash
            redirect omniauth_login_failure_redirect
          end
        end

        if omniauth_identity
          update_omniauth_identity
        else
          create_omniauth_identity
        end
      end

      login("omniauth") do
        two_factor_update_session("omniauth-two") if omniauth_second_factor?
      end
    end

    def omniauth_identity
      @omniauth_identity ||= retrieve_omniauth_identity
    end

    def retrieve_omniauth_identity
      _retrieve_omniauth_identity(omniauth_provider, omniauth_uid)
    end

    def account_from_omniauth_identity
      @account = _account_from_omniauth_identity
    end

    def account_from_omniauth
      @account = _account_from_omniauth
    end

    def omniauth_new_account
      @account = _omniauth_new_account(omniauth_email)
    end

    def omniauth_save_account
      account[account_id_column] = db[accounts_table].insert(account)
    end

    def remove_omniauth_identities
      omniauth_account_identities_ds.delete
    end

    def possible_authentication_methods
      methods = super
      methods << "omniauth" unless methods.include?("password") || (features.include?(:email_auth) && allow_email_auth?) || omniauth_account_identities_ds.empty?
      methods
    end

    private

    def before_confirm_password
      authenticated_by.delete("omniauth")
      super if defined?(super)
    end

    def after_close_account
      super if defined?(super)
      remove_omniauth_identities
    end

    def omniauth_second_factor?
      features.include?(:two_factor_base) && uses_two_factor_authentication? && omniauth_two_factors?
    end

    def omniauth_verify_account?
      features.include?(:verify_account) && account[login_column] == omniauth_email
    end

    def omniauth_verify_account
      transaction do
        verify_account
        remove_verify_account_key
      end
    end

    def omniauth_create_account?
      true
    end

    def omniauth_create_account
      omniauth_new_account
      before_omniauth_create_account
      omniauth_save_account
      after_omniauth_create_account
    end

    def _omniauth_new_account(login)
      acc = { login_column => login }
      unless skip_status_checks?
        acc[account_status_column] = account_open_status_value
      end
      acc
    end

    def create_omniauth_identity
      identity_id = omniauth_identities_ds.insert(omniauth_identity_insert_hash)
      @omniauth_identity = { omniauth_identities_id_column => identity_id }
    end

    def update_omniauth_identity(identity_id = omniauth_identity_id)
      update_hash = omniauth_identity_update_hash
      return if update_hash.empty?

      omniauth_identities_ds
        .where(omniauth_identities_id_column => identity_id)
        .update(update_hash)
    end

    def omniauth_identity_insert_hash
      {
        omniauth_identities_account_id_column => account_id,
        omniauth_identities_provider_column => omniauth_provider.to_s,
        omniauth_identities_uid_column => omniauth_uid,
      }.merge(omniauth_identity_update_hash)
    end

    def omniauth_identity_update_hash
      {}
    end

    def _retrieve_omniauth_identity(provider, uid)
      omniauth_identities_ds.first(
        omniauth_identities_provider_column => provider.to_s,
        omniauth_identities_uid_column => uid,
      )
    end

    def _account_from_omniauth
      _account_from_login(omniauth_email)
    end

    def _account_from_omniauth_identity
      _account_from_id(omniauth_identity_account_id)
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
  end
end

if defined?(Rodauth::Model)
  Rodauth::Model.register_association(:omniauth) do
    { name: :identities, type: :many, table: omniauth_identities_table, key: omniauth_identities_account_id_column }
  end
end

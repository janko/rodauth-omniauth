# frozen_string_literal: true

require "omniauth"

module Rodauth
  Feature.define(:omniauth, :Omniauth) do
    depends :omniauth_base, :login

    before :omniauth_callback_route
    before :omniauth_create_account
    after :omniauth_create_account

    auth_value_method :omniauth_identities_table, :account_identities
    auth_value_method :omniauth_identities_id_column, :id
    auth_value_method :omniauth_identities_account_id_column, :account_id
    auth_value_method :omniauth_identities_provider_column, :provider
    auth_value_method :omniauth_identities_uid_column, :uid
    auth_value_method :omniauth_identities_info_column, :info
    auth_value_method :omniauth_identities_credentials_column, :credentials
    auth_value_method :omniauth_identities_extra_column, :extra

    auth_value_method :update_omniauth_identity?, true
    auth_value_method :omniauth_create_account?, true

    auth_methods(
      :omniauth_create_account,
      :get_omniauth_identities,
      :create_omniauth_identity,
      :omniauth_identity_insert_hash,
      :omniauth_identity_update_hash,
      :remove_omniauth_identities,
      :serialize_omniauth_data,
      :update_omniauth_identity,
      :omniauth_save_account,
    )

    auth_private_methods(
      :retrieve_omniauth_identity,
      :account_from_omniauth_identity,
      :omniauth_new_account,
    )

    def route_omniauth!
      result = super

      omniauth_providers.each do |provider|
        handle_omniauth_callback(provider)
      end

      result
    end

    def handle_omniauth_callback(provider)
      request.is "#{omniauth_prefix[1..-1]}#{provider}/callback" do
        before_omniauth_callback_route
        account_from_session if logged_in?

        retrieve_omniauth_identity

        if omniauth_identity && !account
          account_from_omniauth_identity
        end

        unless account
          account_from_login(omniauth_email)
        end

        if account && !open_account?
          set_redirect_error_status unopen_account_error_status
          set_redirect_error_flash "#{login_error_flash} (#{unverified_account_message})"
          redirect omniauth_failure_redirect
        end

        transaction do
          if omniauth_identity
            update_omniauth_identity if update_omniauth_identity?
          else
            create_omniauth_identity
          end

          unless account
            before_omniauth_create_account
            omniauth_create_account
            after_omniauth_create_account
          end

          # if add_omniauth_identity?
          #   add_omniauth_identity
          # end
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

    def omniauth_create_account
      omniauth_new_account
      omniauth_save_account
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

    def omniauth_remove(provider)
      omniauth_account_identities_ds
        .where(omniauth_identities_provider_column => provider.to_s)
        .delete
    end

    def possible_authentication_methods
      methods = super
      methods << "omniauth" if !methods.include?("password") && omniauth_connected_providers.any?
      methods
    end

    def login_notice_flash
      if @omniauth_account_created
        create_account_notice_flash
      else
        super
      end
    end

    private

    attr_reader :omniauth_identity

    def create_omniauth_identity
      identity_id = omniauth_identities_ds.insert(omniauth_identity_insert_hash)
      @omniauth_identity = { omniauth_identities_id_column => identity_id }
    end

    def update_omniauth_identity(identity_id = omniauth_identity_id)
      omniauth_identities_ds
        .where(omniauth_identities_id_column => identity_id)
        .update(omniauth_identity_update_hash)
    end

    def omniauth_identity_insert_hash
      {
        omniauth_identities_provider_column => omniauth_provider.to_s,
        omniauth_identities_uid_column => omniauth_uid,
      }.merge(omniauth_identity_update_hash)
    end

    def omniauth_identity_update_hash
      {
        omniauth_identities_info_column => serialize_omniauth_data(omniauth_info),
        omniauth_identities_credentials_column => serialize_omniauth_data(omniauth_credentials),
        omniauth_identities_extra_column => serialize_omniauth_data(omniauth_extra),
      }
    end

    def _retrieve_omniauth_identity(provider, uid)
      omniauth_identities_ds.first(
        omniauth_identities_provider_column => provider.to_s,
        omniauth_identities_uid_column => uid,
      )
    end

    def _account_from_omniauth_identity
      account_ds(omniauth_identity_account_id).first
    end

    def omniauth_new_account
      @account = _omniauth_new_account(omniauth_email)
    end

    def omniauth_save_account
      account[account_id_column] = db[accounts_table].insert(account)
    end

    def _omniauth_new_account(login)
      acc = { login_column => login }
      unless skip_status_checks?
        acc[account_status_column] = account_open_status_value
      end
      acc
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

    def serialize_omniauth_data(data)
      data.to_json
    end

    def template_path(page)
      path = "#{__dir__}/../../../templates/#{page}.str"
      File.exist?(path) ? path : super
    end
  end
end

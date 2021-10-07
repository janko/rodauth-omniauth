module Rodauth
  Feature.define(:omniauth_create_account, :OmniauthCreateAccount) do
    depends :omniauth, :create_account

    auth_value_method :omniauth_identity_id_param, "identity_id"

    def create_account_additional_form_tags
      if param(omniauth_identity_id_param)
        super.to_s + omniauth_identity_id_hidden_field
      else
        super
      end
    end

    def create_account_set_password?
      param(omniauth_identity_id_param)
    end

    def verify_account_set_password?
      false
    end

    private

    def omniauth_create_account
      redirect omniauth_create_account_path({
        omniauth_identity_id_param => omniauth_identity_id,
        login_param                => omniauth_email,
      })
    end

    def omniauth_identity_id_hidden_field
      %(<input type="hidden" name="#{omniauth_identity_id_param}" value=\"#{scope.h param(omniauth_identity_id_param)}\" />)
    end
  end
end

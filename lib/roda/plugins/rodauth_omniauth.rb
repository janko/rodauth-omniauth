class Roda
  module RodaPlugins
    module RodauthOmniauth
      module RequestMethods
        def rodauth_omniauth(name = nil)
          scope.rodauth(name).route_omniauth!
        end
        alias omniauth rodauth_omniauth
      end
    end

    register_plugin(:rodauth_omniauth, RodauthOmniauth)
  end
end

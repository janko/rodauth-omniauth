Gem::Specification.new do |spec|
  spec.name          = "rodauth-omniauth"
  spec.version       = "0.6.2"
  spec.authors       = ["Janko Marohnić"]
  spec.email         = ["janko@hey.com"]

  spec.summary       = "Rodauth extension for logging in and creating account via OmniAuth authentication."
  spec.description   = "Rodauth extension for logging in and creating account via OmniAuth authentication."
  spec.homepage      = "https://github.com/janko/rodauth-omniauth"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 2.5"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files         = Dir["README.md", "LICENSE.txt", "*.gemspec", "lib/**/*", "locales/**/*"]
  spec.require_paths = ["lib"]

  spec.add_dependency "rodauth", "~> 2.36"
  spec.add_dependency "omniauth", "~> 2.0"

  spec.add_development_dependency "minitest"
  spec.add_development_dependency "minitest-hooks"
  spec.add_development_dependency "tilt"
  spec.add_development_dependency "bcrypt"
  spec.add_development_dependency "mail"
  spec.add_development_dependency "net-smtp"
  spec.add_development_dependency "capybara"
  spec.add_development_dependency "jwt"
  spec.add_development_dependency "rodauth-i18n"
  spec.add_development_dependency "rodauth-model"
end

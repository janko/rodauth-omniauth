Gem::Specification.new do |spec|
  spec.name          = "rodauth-omniauth"
  spec.version       = "0.1.0"
  spec.authors       = ["Janko Marohnić"]
  spec.email         = ["janko.marohnic@gmail.com"]

  spec.summary       = "Rodauth extension for logging in and creating account via OmniAuth authentication."
  spec.description   = "Rodauth extension for logging in and creating account via OmniAuth authentication."
  spec.homepage      = "https://github.com/janko/rodauth-omniauth"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 2.3"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files         = Dir["README.md", "LICENSE.txt", "*.gemspec", "lib/**/*"]
  spec.require_paths = ["lib"]

  spec.add_dependency "rodauth", "~> 2.0"
  spec.add_dependency "omniauth", "~> 1.6"

  spec.add_development_dependency "minitest"
  spec.add_development_dependency "minitest-hooks"
  spec.add_development_dependency "tilt"
  spec.add_development_dependency "bcrypt"
  spec.add_development_dependency "capybara"
end

$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "user_service/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "user_service"
  s.version     = UserService::VERSION
  s.authors     = ["Arman"]
  s.email       = ["arman.sarrafi@customerservice.nsw.gov.au"]
  s.homepage    = ""
  s.summary     = "Summary of UserService."
  s.description = "Description of UserService."
  s.license     = "MIT"

  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
end

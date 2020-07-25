module UserService
  class Engine < ::Rails::Engine
    isolate_namespace UserService
    config.generators.api_only = true
  end
end

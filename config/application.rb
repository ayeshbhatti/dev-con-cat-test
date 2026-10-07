require_relative "boot"
require "rails/all"

Bundler.require(*Rails.groups)

module SuperPixel
  class Application < Rails::Application
    config.load_defaults 7.1
    config.time_zone = "UTC"
    config.active_record.schema_format = :ruby
    config.active_job.queue_adapter = :async
    config.generators.system_tests = nil
    config.middleware.insert_before 0, Rack::Cors do
      allow do
        origins "*"
        resource "/api/pixel/*", headers: :any, methods: %i[get post options], expose: %w[Content-Type], max_age: 600
      end
    end
  end
end

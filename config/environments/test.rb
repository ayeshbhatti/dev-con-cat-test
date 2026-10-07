require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = false
  config.consider_all_requests_local = true
  config.action_controller.perform_caching = false
  config.action_dispatch.show_exceptions = :rescuable
  config.active_support.deprecation = :stderr
  config.active_job.queue_adapter = :test
  config.action_controller.allow_forgery_protection = false
end

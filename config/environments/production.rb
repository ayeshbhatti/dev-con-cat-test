require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true
  config.force_ssl = ENV["FORCE_SSL"] == "true"
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.active_job.queue_adapter = :async
  config.secret_key_base = ENV.fetch("SECRET_KEY_BASE")
end

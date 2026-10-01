# frozen_string_literal: true

require_relative 'boot'

require 'rails'
# Pick the frameworks you want:
require 'active_model/railtie'
require 'active_job/railtie'
require 'active_record/railtie'
require 'active_storage/engine'
require 'action_controller/railtie'
require 'action_mailer/railtie'
require 'action_mailbox/engine'
require 'action_text/engine'
require 'action_view/railtie'
require 'action_cable/engine'
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module SpreeStarter
  class Application < Rails::Application
    # Active Record Encryption keys (OAuth client secrets use `encrypts`).
    # Set here — not in an initializer — because ActiveRecord copies this
    # config before app initializers run. Derived from secret_key_base so no
    # credentials files or extra env vars are needed; keys rotate only if
    # SECRET_KEY_BASE changes. Test env uses fixed disposable keys.
    if Rails.env.test?
      config.active_record.encryption.primary_key = 'test-oauth-primary-key-000000000'
      config.active_record.encryption.deterministic_key = 'test-oauth-deterministic-0000000'
      config.active_record.encryption.key_derivation_salt = 'test-oauth-salt-0000000000000000'
    else
      config.after_initialize do
        generator = Rails.application.key_generator
        ActiveRecord::Encryption.config.primary_key =
          generator.generate_key('arghamart active record encryption primary', 32)
        ActiveRecord::Encryption.config.deterministic_key =
          generator.generate_key('arghamart active record encryption deterministic', 32)
        ActiveRecord::Encryption.config.key_derivation_salt =
          generator.generate_key('arghamart active record encryption salt', 32)
      end
    end

    config.to_prepare do
      # Load application's model / class decorators
      Dir.glob(File.join(File.dirname(__FILE__), '../app/**/*_decorator*.rb')) do |c|
        Rails.configuration.cache_classes ? require(c) : load(c)
      end
    end
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Don't generate system test files.
    config.generators.system_tests = nil

    # Solid Queue: jobs live in Postgres and, by default, execute inside the
    # Puma process (see config/puma.rb). Scale out by setting
    # SOLID_QUEUE_IN_PUMA=false and running `bin/jobs` as a separate service.
    config.active_job.queue_adapter = :solid_queue

    # The /jobs dashboard uses Mission Control's HTTP Basic auth, independent
    # of app sessions. In production set both env vars — without them the
    # dashboard stays locked. Dev and test fall back to the seed admin
    # credentials.
    config.mission_control.jobs.http_basic_auth_user =
      ENV.fetch("MISSION_CONTROL_USER") { "spree" if Rails.env.local? }
    config.mission_control.jobs.http_basic_auth_password =
      ENV.fetch("MISSION_CONTROL_PASSWORD") { "spree123" if Rails.env.local? }

    config.action_mailer.deliver_later_queue_name = :mailers
    config.active_storage.queues.purge = :active_storage_purge
    config.active_storage.queues.analysis = :active_storage_analysis
    config.active_storage.queues.transform = :active_storage_transform
  end
end

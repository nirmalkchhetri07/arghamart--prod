# frozen_string_literal: true

# Social-login provider registry.
#
# Adding a provider later means: one verifier class implementing
# `.verify(credential, provider_record)` returning
# `{ uid:, email:, email_verified:, first_name:, last_name: }`, plus one
# entry below. Authorization-code providers use the record's client_secret;
# the Google ID-token flow needs only client_id.
module Spree
  module Oauth
    module Providers
      Entry = Data.define(:key, :label, :verifier_class, :implemented, :needs_secret)

      REGISTRY = [
        Entry.new('google', 'Google', GoogleVerifier, true, false),
        Entry.new('facebook', 'Facebook', FacebookVerifier, false, true),
        Entry.new('github', 'GitHub', GithubVerifier, false, true)
      ].freeze

      def self.all
        REGISTRY
      end

      def self.keys
        REGISTRY.map(&:key)
      end

      # Providers a customer can actually use right now (implemented AND
      # with an enabled admin-configured record is checked by callers).
      def self.implemented
        REGISTRY.select(&:implemented)
      end

      def self.find(key)
        REGISTRY.find { |entry| entry.key == key.to_s }
      end

      def self.verifier_for(key)
        find(key)&.verifier_class ||
          raise(ArgumentError, "Unknown OAuth provider: #{key}")
      end

      def self.implemented?(key)
        find(key)&.implemented || false
      end
    end
  end
end

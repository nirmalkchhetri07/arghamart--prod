# frozen_string_literal: true

# Social-login provider registry.
#
# Adding a provider later means: one verifier class implementing
# `.verify(credential, provider_record, redirect_uri: nil)` returning
# `{ uid:, email:, email_verified:, first_name:, last_name: }`, plus one
# entry below. Authorization-code providers (Facebook, GitHub) exchange the
# code with the record's client_secret server-side and require the exact
# `redirect_uri` the storefront used; the Google ID-token flow needs only
# client_id and ignores redirect_uri.
module Spree
  module Oauth
    module Providers
      Entry = Data.define(:key, :label, :verifier_class, :implemented, :needs_secret)

      REGISTRY = [
        Entry.new('google', 'Google', GoogleVerifier, true, false),
        Entry.new('facebook', 'Facebook', FacebookVerifier, true, true),
        Entry.new('github', 'GitHub', GithubVerifier, true, true)
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

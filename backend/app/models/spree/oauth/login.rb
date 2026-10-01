# frozen_string_literal: true

# Resolves a verified OAuth credential to a customer account:
# existing identity (provider+uid) wins, else the verified email links to
# its account, else a new account is created (random password — the
# customer signs in via the provider, never with it). The identity row is
# created or refreshed on every login.
module Spree
  module Oauth
    class Login
      def self.call(provider_key, credential, redirect_uri: nil)
        new(provider_key, credential, redirect_uri: redirect_uri).call
      end

      def initialize(provider_key, credential, redirect_uri: nil)
        @provider_key = provider_key.to_s
        @credential = credential.to_s
        @redirect_uri = redirect_uri.to_s.presence
      end

      def call
        record = Spree::OauthProvider.enabled.find_by(provider: @provider_key)
        raise InvalidToken, "Unknown or disabled OAuth provider: #{@provider_key}" if record.nil?

        verified = record.verifier.verify(@credential, record, redirect_uri: @redirect_uri)
        raise EmailNotVerified, 'Email address is not verified' unless verified[:email_verified]
        raise InvalidToken, 'Verified email is missing' if verified[:email].blank?

        identity = Spree::OauthIdentity.find_by(provider: record.provider, uid: verified[:uid])
        user = identity&.user
        user ||= Spree.user_class.find_by(email: verified[:email])
        user ||= create_user(verified)

        identity ||= Spree::OauthIdentity.new(provider: record.provider, uid: verified[:uid])
        identity.user ||= user
        identity.email = verified[:email]
        identity.save!

        user
      end

      private

      def create_user(verified)
        password = SecureRandom.hex(16)
        Spree.user_class.create!(
          email: verified[:email],
          password: password,
          password_confirmation: password,
          first_name: verified[:first_name],
          last_name: verified[:last_name]
        )
      end
    end
  end
end

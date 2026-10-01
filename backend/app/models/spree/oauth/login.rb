# frozen_string_literal: true

# Resolves a verified OAuth credential to a customer account.
#
# Resolution rules (checked in order):
# 1. An existing identity (provider+uid) wins — log that user in.
# 2. A verified email (Google) links to its account, or creates a new one
#    (random password — the customer signs in via the provider, never
#    with it).
# 3. A missing email raises EmailMissing — the controller asks the customer
#    for an email instead of creating an unusable account.
# 4. An unverified email (Facebook) with no matching user creates the user
#    and identity.
# 5. An unverified email that already belongs to a user raises
#    AccountExists — the identity links only after password proof, so a
#    provider account can never hijack a password account.
#
# The identity row is created or refreshed on every successful login.
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
        uid = verified[:uid].to_s
        raise InvalidToken, 'Verified account id is missing' if uid.blank?

        identity = Spree::OauthIdentity.find_by(provider: record.provider, uid: uid)
        return refresh_identity(identity, verified) if identity&.user

        email = verified[:email].to_s.presence
        user = resolve_user(record, verified, uid, email)
        link_identity!(record, uid, user, email)
        user
      end

      private

      def resolve_user(record, verified, uid, email)
        if verified[:email_verified] && email
          Spree.user_class.find_by(email: email) || create_user(verified.merge(email: email))
        elsif email.nil?
          raise EmailMissing.new('Email address is missing', identity_payload(record, verified, uid, nil))
        elsif Spree.user_class.find_by(email: email)
          raise AccountExists.new(
            'An account with this email already exists. Sign in with your password to link it.',
            identity_payload(record, verified, uid, email)
          )
        else
          create_user(verified.merge(email: email))
        end
      end

      def refresh_identity(identity, verified)
        email = verified[:email].to_s.presence
        identity.update!(email: email) if email && identity.email != email
        identity.user
      end

      def link_identity!(record, uid, user, email)
        identity = Spree::OauthIdentity.find_or_initialize_by(provider: record.provider, uid: uid)
        identity.user = user
        identity.email = email
        identity.save!
      end

      def identity_payload(record, verified, uid, email)
        {
          provider: record.provider,
          uid: uid,
          email: email,
          first_name: verified[:first_name],
          last_name: verified[:last_name]
        }
      end

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

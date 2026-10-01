# frozen_string_literal: true

# Short-lived, single-use tokens that carry an unverified OAuth identity
# through the email-collection / password-confirmation steps.
#
# Signed with secret_key_base (purpose-bound, 10-minute expiry) via
# Rails.application.message_verifier — no database table, no secrets in
# env vars. Single-use is enforced with a cache marker keyed by the token's
# random jti: the first consume writes the marker with `unless_exist`, so a
# replayed token is rejected even if it has not expired yet.
module Spree
  module Oauth
    class PendingToken
      VERIFIER_NAME = 'spree_oauth_pending'
      PURPOSE = 'oauth_pending'
      EXPIRY = 10.minutes
      MARKER_EXPIRY = EXPIRY + 1.minute

      EMAIL_MISSING = 'email_missing'
      ACCOUNT_EXISTS = 'account_exists_confirm_required'

      # `identity` is a hash: { provider:, uid:, email:, first_name:,
      # last_name: }.
      def self.mint(purpose:, identity:)
        payload = {
          'provider' => identity[:provider].to_s,
          'uid' => identity[:uid].to_s,
          'email' => identity[:email].to_s.presence,
          'first_name' => identity[:first_name].to_s.presence,
          'last_name' => identity[:last_name].to_s.presence,
          'purpose' => purpose.to_s,
          'jti' => SecureRandom.hex(16)
        }
        verifier.generate(payload, expires_in: EXPIRY, purpose: PURPOSE)
      end

      # Returns the payload hash, or raises InvalidToken when the token is
      # tampered with, expired, or already consumed.
      def self.consume(token)
        payload = verifier.verified(token.to_s, purpose: PURPOSE)
        raise InvalidToken, 'This sign-in link has expired. Please try again.' if payload.nil?
        raise InvalidToken, 'Unknown sign-in request.' unless [EMAIL_MISSING, ACCOUNT_EXISTS].include?(payload['purpose'])

        marker = "oauth_pending_used:#{payload['jti']}"
        unless Rails.cache.write(marker, true, expires_in: MARKER_EXPIRY, unless_exist: true)
          raise InvalidToken, 'This sign-in link has already been used. Please try again.'
        end

        payload
      end

      def self.verifier
        Rails.application.message_verifier(VERIFIER_NAME)
      end
      private_class_method :verifier
    end
  end
end

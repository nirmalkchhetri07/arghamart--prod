# frozen_string_literal: true

require 'googleauth/id_tokens'

# Verifies a Google Identity Services ID token (JWT) against the provider
# record's client_id as audience. Returns the stable subject id, the
# verified email claim, and profile names for new-account creation.
module Spree
  module Oauth
    class GoogleVerifier
      # redirect_uri is accepted for a uniform verifier interface (see
      # Spree::Oauth::Login) and ignored: the ID-token flow needs only the
      # audience (client_id), never a server-side exchange.
      # rubocop:disable Lint/UnusedMethodArgument
      def self.verify(credential, provider_record, redirect_uri: nil)
        # rubocop:enable Lint/UnusedMethodArgument
        payload = Google::Auth::IDTokens.verify_oidc(
          credential.to_s, aud: provider_record.client_id
        )
        {
          uid: payload['sub'],
          email: payload['email'],
          email_verified: payload['email_verified'] == true,
          first_name: payload['given_name'],
          last_name: payload['family_name']
        }
      rescue Google::Auth::IDTokens::VerificationError,
             Google::Auth::IDTokens::KeySourceError => e
        raise InvalidToken, "Google token verification failed: #{e.class}"
      end
    end
  end
end

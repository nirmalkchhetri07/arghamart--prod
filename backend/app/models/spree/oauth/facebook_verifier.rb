# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'openssl'

# Verifies a Facebook Login user access token (from the storefront's FB SDK
# popup or the /fb-callback redirect flow) server-side.
#
# 1. `debug_token` with `<app_id>|<app_secret>` proves the token was issued
#    for our app, is valid, and is not expired.
# 2. `/me` reads the profile the token belongs to (with `appsecret_proof`,
#    so a leaked token alone is not enough to impersonate the call).
#
# Facebook exposes no email-verified flag, so `email_verified` is always
# false — Spree::Oauth::Login decides from the account-resolution rules
# whether to create, link-after-password-proof, or ask for an email.
# Tokens and the app secret are never logged (see
# config/initializers/filter_parameter_logging.rb).
module Spree
  module Oauth
    class FacebookVerifier
      GRAPH_VERSION = 'v20.0'
      OPEN_TIMEOUT = 10
      READ_TIMEOUT = 15

      def self.verify(credential, provider_record, redirect_uri: nil) # rubocop:disable Lint/UnusedMethodArgument
        # Accepted for a uniform verifier interface (see Spree::Oauth::Login);
        # the token flow needs no redirect_uri.
        token = credential.to_s
        raise InvalidToken, 'Access token is required' if token.blank?
        raise InvalidToken, 'Facebook client secret is not configured' if provider_record.client_secret.blank?

        debug_token(token, provider_record)
        profile = fetch_profile(token, provider_record.client_secret)

        uid = profile['id'].to_s
        raise InvalidToken, 'Facebook account id is missing' if uid.blank?

        {
          uid: uid,
          email: profile['email'].to_s.presence,
          email_verified: false,
          first_name: profile['first_name'].presence,
          last_name: profile['last_name'].presence
        }
      end

      def self.debug_token(token, provider_record)
        uri = URI.parse("https://graph.facebook.com/#{GRAPH_VERSION}/debug_token")
        uri.query = URI.encode_www_form(
          input_token: token,
          access_token: "#{provider_record.client_id}|#{provider_record.client_secret}"
        )
        body = get_json(uri, 'Facebook token inspection')
        data = body['data']

        raise InvalidToken, "Facebook token inspection failed: #{provider_message(body)}" unless data.is_a?(Hash)
        raise InvalidToken, 'Facebook token is not valid' unless data['is_valid'] == true
        raise InvalidToken, 'Facebook token was issued for a different app' if data['app_id'].to_s != provider_record.client_id.to_s

        expires_at = data['expires_at'].to_i
        # expires_at is a unix timestamp; 0 means the token never expires.
        raise InvalidToken, 'Facebook token is expired' if expires_at.positive? && expires_at <= Time.now.to_i

        data
      end
      private_class_method :debug_token

      def self.fetch_profile(token, client_secret)
        uri = URI.parse("https://graph.facebook.com/#{GRAPH_VERSION}/me")
        uri.query = URI.encode_www_form(
          fields: 'id,email,first_name,last_name',
          access_token: token,
          appsecret_proof: appsecret_proof(token, client_secret)
        )
        body = get_json(uri, 'Facebook profile fetch')
        raise InvalidToken, "Facebook profile fetch failed: #{provider_message(body)}" if body['error'].present?

        body
      end
      private_class_method :fetch_profile

      def self.appsecret_proof(token, client_secret)
        OpenSSL::HMAC.hexdigest('SHA256', client_secret.to_s, token.to_s)
      end
      private_class_method :appsecret_proof

      def self.get_json(uri, context)
        response = begin
          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                              open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
            http.request(Net::HTTP::Get.new(uri.request_uri))
          end
        rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
          raise InvalidToken, "Facebook verification failed: #{e.class}"
        end
        begin
          body = JSON.parse(response.body.to_s)
        rescue JSON::ParserError
          raise InvalidToken, "#{context} failed: invalid response"
        end
        unless response.is_a?(Net::HTTPSuccess)
          detail = body.is_a?(Hash) ? provider_message(body) : "HTTP #{response.code}"
          raise InvalidToken, "#{context} failed: #{detail}"
        end

        body
      end
      private_class_method :get_json

      def self.provider_message(body)
        body.dig('error', 'message').to_s.truncate(200).presence || 'unknown provider error'
      end
      private_class_method :provider_message
    end
  end
end

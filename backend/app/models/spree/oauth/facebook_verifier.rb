# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

# Verifies a Facebook Login authorization code via server-side exchange.
#
# The storefront redirects the customer to Facebook's OAuth dialog and posts
# the returned `code` (as `credential`) plus the exact `redirect_uri` it
# used to POST /api/v3/store/auth/facebook. We exchange the code with the
# record's client_secret, then fetch the profile. The secret never leaves
# the server.
module Spree
  module Oauth
    class FacebookVerifier
      GRAPH_VERSION = 'v20.0'
      OPEN_TIMEOUT = 10
      READ_TIMEOUT = 15

      def self.verify(credential, provider_record, redirect_uri: nil)
        code = credential.to_s
        raise InvalidToken, 'Authorization code is required' if code.blank?
        raise InvalidToken, 'Facebook client secret is not configured' if provider_record.client_secret.blank?
        raise InvalidToken, 'redirect_uri is required' if redirect_uri.to_s.blank?

        access_token = exchange_code(
          code: code,
          client_id: provider_record.client_id,
          client_secret: provider_record.client_secret,
          redirect_uri: redirect_uri.to_s
        )
        profile = fetch_profile(access_token)

        uid = profile['id'].to_s
        email = profile['email'].to_s.presence
        raise InvalidToken, 'Facebook account id is missing' if uid.blank?
        raise InvalidToken, 'Verified email is missing' if email.blank?

        # Facebook only returns an email address the user confirmed on
        # Facebook, so a present email counts as verified. A missing email
        # (permission denied) is rejected above.
        {
          uid: uid,
          email: email,
          email_verified: true,
          first_name: profile['first_name'].presence,
          last_name: profile['last_name'].presence
        }
      end

      def self.exchange_code(code:, client_id:, client_secret:, redirect_uri:)
        uri = URI.parse("https://graph.facebook.com/#{GRAPH_VERSION}/oauth/access_token")
        uri.query = URI.encode_www_form(
          client_id: client_id,
          client_secret: client_secret,
          redirect_uri: redirect_uri,
          code: code
        )
        body = get_json(uri, 'Facebook code exchange')
        token = body['access_token'].to_s.presence
        raise InvalidToken, "Facebook code exchange failed: #{provider_message(body)}" if token.nil?

        token
      end
      private_class_method :exchange_code

      def self.fetch_profile(access_token)
        uri = URI.parse("https://graph.facebook.com/#{GRAPH_VERSION}/me")
        uri.query = URI.encode_www_form(
          fields: 'id,first_name,last_name,email',
          access_token: access_token
        )
        body = get_json(uri, 'Facebook profile fetch')
        raise InvalidToken, "Facebook profile fetch failed: #{provider_message(body)}" if body['error'].present?

        body
      end
      private_class_method :fetch_profile

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

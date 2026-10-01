# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

# Verifies a GitHub OAuth authorization code via server-side exchange.
#
# The storefront redirects the customer to github.com/login/oauth/authorize
# and posts the returned `code` (as `credential`) plus the exact
# `redirect_uri` it used to POST /api/v3/store/auth/github. We exchange the
# code with the record's client_secret, then read the user profile and the
# verified primary email. The secret never leaves the server.
module Spree
  module Oauth
    class GithubVerifier
      OPEN_TIMEOUT = 10
      READ_TIMEOUT = 15
      USER_AGENT = 'Spree-OAuth'

      def self.verify(credential, provider_record, redirect_uri: nil)
        code = credential.to_s
        raise InvalidToken, 'Authorization code is required' if code.blank?
        raise InvalidToken, 'GitHub client secret is not configured' if provider_record.client_secret.blank?
        raise InvalidToken, 'redirect_uri is required' if redirect_uri.to_s.blank?

        access_token = exchange_code(
          code: code,
          client_id: provider_record.client_id,
          client_secret: provider_record.client_secret,
          redirect_uri: redirect_uri.to_s
        )
        profile = fetch_user(access_token)
        email, verified = resolve_email(access_token, profile)

        uid = profile['id'].to_s
        raise InvalidToken, 'GitHub account id is missing' if uid.blank?
        raise InvalidToken, 'Verified email is missing' if email.blank?
        raise EmailNotVerified, 'Email address is not verified' unless verified

        first_name, last_name = split_name(profile['name'])
        {
          uid: uid,
          email: email,
          email_verified: true,
          first_name: first_name,
          last_name: last_name
        }
      end

      def self.exchange_code(code:, client_id:, client_secret:, redirect_uri:)
        uri = URI.parse('https://github.com/login/oauth/access_token')
        body = post_json(uri, {
                           client_id: client_id,
                           client_secret: client_secret,
                           code: code,
                           redirect_uri: redirect_uri
                         }, 'GitHub code exchange')
        token = body['access_token'].to_s.presence
        if token.nil?
          description = body['error_description'].to_s.presence || body['error'].to_s.presence || 'unknown provider error'
          raise InvalidToken, "GitHub code exchange failed: #{description.truncate(200)}"
        end

        token
      end
      private_class_method :exchange_code

      def self.fetch_user(access_token)
        uri = URI.parse('https://api.github.com/user')
        body = get_json(uri, access_token, 'GitHub profile fetch')
        raise InvalidToken, "GitHub profile fetch failed: #{provider_message(body)}" if body['message'].present? && body['id'].nil?

        body
      end
      private_class_method :fetch_user

      # GitHub's public profile email is often null (private emails); the
      # /user/emails list is authoritative for verified addresses.
      def self.resolve_email(access_token, profile)
        emails = fetch_emails(access_token)
        if emails.any?
          selected = emails.find { |e| e['primary'] == true && e['verified'] == true } ||
            emails.find { |e| e['verified'] == true } ||
            emails.find { |e| e['primary'] == true } ||
            emails.first
          return [selected['email'].to_s.presence, selected['verified'] == true]
        end

        # Fall back to the public profile email (treated as unverified —
        # Login refuses it with email_not_verified).
        [profile['email'].to_s.presence, false]
      end
      private_class_method :resolve_email

      def self.fetch_emails(access_token)
        uri = URI.parse('https://api.github.com/user/emails')
        body = get_json(uri, access_token, 'GitHub emails fetch')
        return [] unless body.is_a?(Array)

        body
      end
      private_class_method :fetch_emails

      def self.split_name(full_name)
        parts = full_name.to_s.split(' ', 2).map(&:presence).compact
        [parts[0], parts[1]]
      end
      private_class_method :split_name

      def self.api_headers(access_token)
        {
          'Accept' => 'application/vnd.github+json',
          'Authorization' => "Bearer #{access_token}",
          'X-GitHub-Api-Version' => '2022-11-28',
          'User-Agent' => USER_AGENT
        }
      end
      private_class_method :api_headers

      def self.post_json(uri, payload, context)
        response = begin
          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                              open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
            request = Net::HTTP::Post.new(uri.request_uri)
            request['Content-Type'] = 'application/json'
            request['Accept'] = 'application/json'
            request.body = payload.to_json
            http.request(request)
          end
        rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
          raise InvalidToken, "GitHub verification failed: #{e.class}"
        end
        begin
          body = JSON.parse(response.body.to_s)
        rescue JSON::ParserError
          raise InvalidToken, "#{context} failed: invalid response"
        end
        unless response.is_a?(Net::HTTPSuccess)
          detail = body.is_a?(Hash) ? github_message(body) : "HTTP #{response.code}"
          raise InvalidToken, "#{context} failed: #{detail}"
        end

        body
      end
      private_class_method :post_json

      def self.get_json(uri, access_token, context)
        response = begin
          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                              open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
            request = Net::HTTP::Get.new(uri.request_uri)
            api_headers(access_token).each { |key, value| request[key] = value }
            http.request(request)
          end
        rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
          raise InvalidToken, "GitHub verification failed: #{e.class}"
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

      def self.github_message(body)
        body['error_description'].to_s.presence || body['error'].to_s.presence ||
          provider_message(body)
      end
      private_class_method :github_message

      def self.provider_message(body)
        body['message'].to_s.truncate(200).presence || 'unknown provider error'
      end
      private_class_method :provider_message
    end
  end
end

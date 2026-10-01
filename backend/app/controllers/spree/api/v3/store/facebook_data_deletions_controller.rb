# frozen_string_literal: true

require 'openssl'
require 'json'

module Spree
  module Api
    module V3
      module Store
        # Facebook data-deletion callback (Settings → Basic → Data Deletion
        # Request URL in the Meta app dashboard).
        #
        # POST /api/v3/store/facebook/data_deletion with { signed_request }
        #
        # Facebook signs the request with the app secret (HMAC-SHA256 over
        # the payload segment). The secret is read from the admin-configured
        # Facebook provider record server-side and never leaves the backend.
        # On success the matching OauthIdentity rows are removed — the
        # customer keeps their store account (only the Facebook link is
        # deleted) and the request is logged for manual review.
        #
        # Responds { url, confirmation_code } per Facebook's contract; the
        # url points at the storefront status page where the customer can
        # follow up with the code.
        class FacebookDataDeletionsController < Store::BaseController
          allow_guest_storefront_access!

          skip_before_action :authenticate_user, only: [:create]

          # POST /api/v3/store/facebook/data_deletion
          def create
            if params[:signed_request].blank?
              return render_error(
                code: ERROR_CODES[:invalid_token],
                message: 'signed_request is required',
                status: :bad_request
              )
            end

            record = Spree::OauthProvider.enabled.find_by(provider: 'facebook')
            if record.nil? || record.client_secret.blank?
              return render_error(
                code: 'provider_disabled',
                message: 'Facebook sign-in is currently disabled',
                status: :bad_request
              )
            end

            facebook_uid = verified_user_id(params[:signed_request].to_s, record.client_secret)
            if facebook_uid.nil?
              return render_error(
                code: ERROR_CODES[:invalid_token],
                message: 'Invalid signed_request signature',
                status: :bad_request
              )
            end

            identities = Spree::OauthIdentity.where(provider: 'facebook', uid: facebook_uid)
            removed = identities.size
            identities.delete_all

            Rails.logger.info(
              "[FacebookDataDeletion] removed #{removed} identities for Facebook user id hash " \
              "#{Digest::SHA256.hexdigest("facebook:#{facebook_uid}")[0, 16]} — flagged for manual review"
            )

            confirmation_code = SecureRandom.hex(16)
            Rails.cache.write(
              "facebook_deletion:#{confirmation_code}",
              { facebook_uid_hash: Digest::SHA256.hexdigest("facebook:#{facebook_uid}"), at: Time.now.utc.iso8601 },
              expires_in: 30.days
            )

            render json: {
              url: data_deletion_status_url(confirmation_code),
              confirmation_code: confirmation_code
            }
          end

          private

          def verified_user_id(signed_request, client_secret)
            encoded_sig, payload = signed_request.split('.', 2)
            return nil if encoded_sig.blank? || payload.blank?

            signature = base64_url_decode(encoded_sig)
            return nil if signature.nil?

            expected = OpenSSL::HMAC.digest('SHA256', client_secret.to_s, payload)
            return nil unless signature.bytesize == expected.bytesize &&
              ActiveSupport::SecurityUtils.secure_compare(signature, expected)

            begin
              data = JSON.parse(base64_url_decode(payload).to_s)
            rescue JSON::ParserError, TypeError
              return nil
            end
            data.is_a?(Hash) ? data['user_id'].to_s.presence : nil
          end

          def base64_url_decode(segment)
            padded = segment.tr('-_', '+/') + ('=' * ((4 - (segment.length % 4)) % 4))
            Base64.strict_decode64(padded)
          rescue ArgumentError
            nil
          end

          def data_deletion_status_url(code)
            storefront_url = ENV['STOREFRONT_URL'].presence || ENV['NEXT_PUBLIC_SITE_URL'].presence
            return "/data-deletion-status?code=#{code}" if storefront_url.blank?

            "#{storefront_url.chomp('/')}/data-deletion-status?code=#{CGI.escape(code)}"
          end
        end
      end
    end
  end
end

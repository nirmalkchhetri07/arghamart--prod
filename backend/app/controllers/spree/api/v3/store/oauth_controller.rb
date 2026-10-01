# frozen_string_literal: true

module Spree
  module Api
    module V3
      module Store
        # Social login for customers.
        #
        # POST /api/v3/store/auth/:provider with { credential, redirect_uri? }
        #
        # Google posts an ID token as `credential`. Facebook/GitHub post the
        # authorization `code` as `credential` plus the exact `redirect_uri`
        # the storefront used at the provider (required for the server-side
        # code exchange; ignored by Google).
        # Verifies the provider credential, resolves (or creates) the
        # customer account, and issues tokens with the exact same shape as
        # the stock login endpoint: it reuses `generate_jwt`,
        # `Spree::RefreshToken.create_for` and the customer serializer
        # instead of reimplementing JWT. Guest-cart merging stays
        # client-side (the storefront associates the cart after login, as
        # with password login).
        #
        # Error codes: invalid_token, provider_disabled, email_not_verified.
        class OauthController < Store::BaseController
          allow_guest_storefront_access!
          # Same brute-force protection as password login.
          rate_limit to: Spree::Api::Config[:rate_limit_login], within: Spree::Api::Config[:rate_limit_window].seconds, store: Rails.cache,
                     only: :create, with: RATE_LIMIT_RESPONSE

          skip_before_action :authenticate_user, only: [:create]

          # POST /api/v3/store/auth/:provider
          def create
            provider_key = params[:provider].to_s

            unless Spree::Oauth::Providers.implemented?(provider_key)
              return render_error(
                code: ERROR_CODES[:invalid_provider],
                message: "Unsupported authentication provider: #{provider_key}",
                status: :bad_request
              )
            end

            unless Spree::OauthProvider.enabled.exists?(provider: provider_key)
              return render_error(
                code: 'provider_disabled',
                message: 'This sign-in method is currently disabled',
                status: :unauthorized
              )
            end

            if params[:credential].blank?
              return render_error(
                code: ERROR_CODES[:invalid_token],
                message: 'credential is required',
                status: :unauthorized
              )
            end

            user = Spree::Oauth::Login.call(provider_key, params[:credential], redirect_uri: params[:redirect_uri])
            render json: auth_response(user)
          rescue Spree::Oauth::EmailNotVerified => e
            render_error(
              code: 'email_not_verified',
              message: e.message,
              status: :unauthorized
            )
          rescue Spree::Oauth::InvalidToken => e
            render_error(
              code: ERROR_CODES[:invalid_token],
              message: e.message,
              status: :unauthorized
            )
          end

          protected

          def serializer_params
            {
              store: current_store,
              locale: current_locale,
              currency: current_currency,
              user: current_user,
              includes: [],
              hide_prices: hide_prices?
            }
          end

          private

          def auth_response(user)
            refresh_token = Spree::RefreshToken.create_for(user, request_env: request_env_for_token)

            {
              token: generate_jwt(user),
              refresh_token: refresh_token.token,
              user: user_serializer.new(user, params: serializer_params).to_h
            }
          end

          def request_env_for_token
            {
              ip_address: request.remote_ip,
              user_agent: request.user_agent&.truncate(255)
            }
          end

          def user_serializer
            Spree.api.customer_serializer
          end
        end
      end
    end
  end
end

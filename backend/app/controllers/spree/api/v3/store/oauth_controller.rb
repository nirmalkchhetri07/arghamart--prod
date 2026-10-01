# frozen_string_literal: true

module Spree
  module Api
    module V3
      module Store
        # Social login for customers.
        #
        # POST /api/v3/store/auth/:provider with { credential, redirect_uri? }
        #
        # Google posts an ID token as `credential`. Facebook posts the user
        # access token from the FB SDK popup (or the /fb-callback redirect
        # flow) as `credential`. GitHub posts the authorization `code` plus
        # the exact `redirect_uri` the storefront used (required for the
        # server-side code exchange; ignored by Google and Facebook).
        #
        # Verifies the provider credential, resolves (or creates) the
        # customer account, and issues tokens with the exact same shape as
        # the stock login endpoint: it reuses `generate_jwt`,
        # `Spree::RefreshToken.create_for` and the customer serializer
        # instead of reimplementing JWT. Guest-cart merging stays
        # client-side (the storefront associates the cart after login, as
        # with password login).
        #
        # Resolution outcomes:
        # - existing identity, verified email, or unverified email without a
        #   matching account: 200 with tokens.
        # - provider gave no email: 422 `email_missing` + `pending_oauth`
        #   token for POST auth/complete.
        # - unverified email already registered: 409
        #   `account_exists_confirm_required` + `pending_oauth` token.
        #
        # Error codes: invalid_token, provider_disabled, email_not_verified,
        # email_missing, account_exists_confirm_required, invalid_credentials.
        class OauthController < Store::BaseController
          allow_guest_storefront_access!
          # Same brute-force protection as password login, on both the
          # initial and the completion step.
          rate_limit to: Spree::Api::Config[:rate_limit_login], within: Spree::Api::Config[:rate_limit_window].seconds, store: Rails.cache,
                     only: %i[create complete], with: RATE_LIMIT_RESPONSE

          skip_before_action :authenticate_user, only: %i[create complete]

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
          rescue Spree::Oauth::EmailMissing => e
            render_pending(
              code: 'email_missing',
              message: 'Facebook did not share an email address. Enter yours to finish signing in.',
              status: :unprocessable_content,
              payload: e.payload,
              purpose: Spree::Oauth::PendingToken::EMAIL_MISSING
            )
          rescue Spree::Oauth::AccountExists => e
            render_pending(
              code: 'account_exists_confirm_required',
              message: e.message,
              status: :conflict,
              payload: e.payload,
              purpose: Spree::Oauth::PendingToken::ACCOUNT_EXISTS
            )
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

          # POST /api/v3/store/auth/complete with
          # { pending_oauth, email?, password? }
          #
          # Finishes the two flows that create/complete cannot:
          # - `email_missing`: the customer supplies an email. It must not
          #   belong to an existing account (else 409 with a fresh
          #   account-exists token); otherwise the user + identity are
          #   created. The app has no confirmable module, so sign-in
          #   proceeds immediately.
          # - `account_exists_confirm_required`: the customer proves
          #   ownership of the existing account with its password, then the
          #   identity links and tokens are issued.
          def complete
            if params[:pending_oauth].blank?
              return render_error(
                code: ERROR_CODES[:invalid_token],
                message: 'pending_oauth is required',
                status: :unauthorized
              )
            end

            payload = Spree::Oauth::PendingToken.consume(params[:pending_oauth])
            record = Spree::OauthProvider.enabled.find_by(provider: payload['provider'])
            if record.nil?
              return render_error(
                code: 'provider_disabled',
                message: 'This sign-in method is currently disabled',
                status: :unauthorized
              )
            end

            case payload['purpose']
            when Spree::Oauth::PendingToken::EMAIL_MISSING
              complete_email_missing(record, payload)
            when Spree::Oauth::PendingToken::ACCOUNT_EXISTS
              complete_account_exists(record, payload)
            end
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

          def render_pending(code:, message:, status:, payload:, purpose:)
            token = Spree::Oauth::PendingToken.mint(
              purpose: purpose,
              identity: {
                provider: payload[:provider] || payload['provider'],
                uid: payload[:uid] || payload['uid'],
                email: payload[:email] || payload['email'],
                first_name: payload[:first_name] || payload['first_name'],
                last_name: payload[:last_name] || payload['last_name']
              }
            )
            render json: {
              error: { code: code, message: message },
              pending_oauth: token
            }, status: status
          end

          def normalize_email(value)
            value.to_s.strip.downcase.presence
          end

          def valid_email?(value)
            value.present? && value.match?(URI::MailTo::EMAIL_REGEXP)
          end

          def complete_email_missing(record, payload)
            email = normalize_email(params[:email])
            unless valid_email?(email)
              return render_error(
                code: 'email_missing',
                message: 'Enter a valid email address to finish signing in.',
                status: :unprocessable_content
              )
            end

            if Spree.user_class.find_by(email: email)
              # The email belongs to an account after all — rotate into the
              # password-proof flow instead of creating a duplicate.
              return render_pending(
                code: 'account_exists_confirm_required',
                message: 'An account with this email already exists. Sign in with your password to link it.',
                status: :conflict,
                payload: payload.merge('email' => email),
                purpose: Spree::Oauth::PendingToken::ACCOUNT_EXISTS
              )
            end

            user = Spree.user_class.create!(
              email: email,
              password: (password = SecureRandom.hex(16)),
              password_confirmation: password,
              first_name: payload['first_name'],
              last_name: payload['last_name']
            )
            Spree::OauthIdentity.create!(provider: record.provider, uid: payload['uid'], user: user, email: email)
            render json: auth_response(user)
          end

          def complete_account_exists(record, payload)
            email = normalize_email(payload['email'])
            user = email && Spree.user_class.find_by(email: email)

            if user.nil? || params[:password].blank? || !user.valid_password?(params[:password].to_s)
              return render_error(
                code: 'invalid_credentials',
                message: 'Incorrect email or password.',
                status: :unauthorized
              )
            end

            identity = Spree::OauthIdentity.find_or_initialize_by(provider: record.provider, uid: payload['uid'])
            identity.user = user
            identity.email = email
            identity.save!
            render json: auth_response(user)
          end
        end
      end
    end
  end
end

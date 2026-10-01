# frozen_string_literal: true

module Spree
  module Api
    module V3
      module Store
        # Public social-login configuration for the storefront sign-in UI.
        #
        # GET /api/v3/store/oauth_providers
        #
        # Returns enabled providers only, as [{ provider, name, client_id }].
        # Secrets are never serialized. Guest-accessible and HTTP-cached like
        # the stock countries endpoint.
        class OauthProvidersController < Store::BaseController
          allow_guest_storefront_access!
          include Spree::Api::V3::HttpCaching

          def index
            providers = Spree::OauthProvider.enabled.ordered

            return unless cache_collection(providers)

            render json: {
              data: providers.filter_map do |provider|
                next unless provider.implemented?

                {
                  provider: provider.provider,
                  name: provider.name,
                  client_id: provider.client_id
                }
              end
            }
          end
        end
      end
    end
  end
end

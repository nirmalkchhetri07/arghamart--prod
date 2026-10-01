# frozen_string_literal: true

module Spree
  module Api
    module V3
      module Store
        module Nepal
          # Public reference data for the Nepal checkout address form.
          #
          # GET /api/v3/store/nepal/provinces
          #
          # Returns all 7 provinces, each with its ACTIVE districts only
          # (deactivated districts are hidden from the storefront dropdown).
          # Guest-accessible and HTTP-cached like the stock countries
          # endpoint — no prices or fees, just ids + names.
          class ProvincesController < Store::BaseController
            allow_guest_storefront_access!
            include Spree::Api::V3::HttpCaching

            def index
              provinces = Spree::Province.includes(:districts).order(:position, :name)

              return unless cache_collection(provinces)

              render json: {
                data: provinces.map do |province|
                  {
                    id: province.prefixed_id,
                    name: province.name,
                    code: province.code,
                    districts: province.districts.select(&:active?).sort_by(&:name).map do |district|
                      { id: district.prefixed_id, name: district.name }
                    end
                  }
                end
              }
            end
          end
        end
      end
    end
  end
end

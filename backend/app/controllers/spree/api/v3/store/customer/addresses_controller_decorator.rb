# frozen_string_literal: true

# Permits Nepal province/district fields on saved-address CRUD
# (POST/PATCH /api/v3/store/customers/me/addresses).
module Spree
  module Api
    module V3
      module Store
        module Customer
          module AddressesControllerDecorator
            protected

            def permitted_params
              super | %i[province_id district_id province_name district_name]
            end
          end

          AddressesController.prepend AddressesControllerDecorator
        end
      end
    end
  end
end

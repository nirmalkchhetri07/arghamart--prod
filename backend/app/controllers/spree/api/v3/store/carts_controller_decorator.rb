# frozen_string_literal: true

# Permits Nepal province/district fields on cart address updates
# (checkout flow: PATCH /api/v3/store/carts/:id).
#
# Accepts both FKs (prefixed prov_xxx / dist_xxx IDs, resolved in
# Spree::AddressDecorator) and name fallbacks for guest flows.
module Spree
  module Api
    module V3
      module Store
        module CartsControllerDecorator
          private

          def address_params
            super + %i[province_id district_id province_name district_name]
          end
        end

        CartsController.prepend CartsControllerDecorator
      end
    end
  end
end

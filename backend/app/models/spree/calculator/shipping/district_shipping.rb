# frozen_string_literal: true

require_dependency 'spree/shipping_calculator'

# Nepal district-based shipping (Part 5).
#
# Returns the shipping_fee of the district on the order's ship address.
# Falls back to `preferred_default_fee` (NPR) when the district is missing,
# inactive, or has no fee configured yet (fee 0) — checkout never raises
# here; the storefront shows a "default fee applied" notice instead.
module Spree
  module Calculator::Shipping
    class DistrictShipping < ShippingCalculator
      preference :default_fee, :decimal, default: 0
      preference :currency, :string, default: -> { Spree::Store.default.default_currency }

      def self.description
        Spree.t(:shipping_district_rate)
      end

      def compute_package(package)
        fee_for(district_for(package.order))
      end

      def compute_shipment(shipment)
        fee_for(district_for(shipment.order))
      end

      private

      def district_for(order)
        order&.ship_address&.district
      end

      def fee_for(district)
        if district.present? && district.active? && district.fee_configured?
          district.shipping_fee
        else
          preferred_default_fee
        end
      end
    end
  end
end

# frozen_string_literal: true

# Exposes Nepal province/district on Store API address payloads (embedded in
# cart/order responses and the customer address endpoints) so the storefront
# can read back the selected district, display its name, and look up the
# shipping fee without an extra request.
#
# province_id / district_id serialize as prefixed IDs (prov_xxx / dist_xxx)
# to match every other Spree API reference. Names + fee are included so the
# checkout summary and saved-address list can render without joining.
module Spree
  module Api
    module V3
      module AddressSerializerDecorator
        def self.prepended(base)
          base.typelize province_id: [:string, { nullable: true }],
                        province_name: [:string, { nullable: true }],
                        district_id: [:string, { nullable: true }],
                        district_name: [:string, { nullable: true }],
                        district_shipping_fee: [:string, { nullable: true }]

          base.attribute :province_id do |address|
            address.province&.prefixed_id
          end

          base.attribute :province_name do |address|
            address.province&.name
          end

          base.attribute :district_id do |address|
            address.district&.prefixed_id
          end

          base.attribute :district_name do |address|
            address.district&.name
          end

          base.attribute :district_shipping_fee do |address|
            address.district&.shipping_fee&.to_s
          end
        end
      end

      AddressSerializer.prepend AddressSerializerDecorator
    end
  end
end

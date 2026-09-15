# frozen_string_literal: true

# Exposes the "Delivered" tracking (see Spree::ShipmentDecorator) on the
# Store API fulfillment payloads (embedded in order/cart responses) so the
# storefront can show delivery status on the customer's order history page.
module Spree
  module Api
    module V3
      module FulfillmentSerializerDecorator
        def self.prepended(base)
          base.typelize delivered_at: [:string, { nullable: true }], delivered: :boolean

          base.attribute :delivered_at do |shipment|
            shipment.delivered_at&.iso8601
          end

          base.attribute :delivered, &:delivered?
        end
      end

      FulfillmentSerializer.prepend FulfillmentSerializerDecorator
    end
  end
end

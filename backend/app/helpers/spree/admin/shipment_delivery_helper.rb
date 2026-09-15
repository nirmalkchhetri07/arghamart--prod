# frozen_string_literal: true

# View helpers for the "Delivered" tracking layered on top of Spree's
# shipment state machine (see Spree::ShipmentDecorator).
module Spree
  module Admin
    module ShipmentDeliveryHelper
      # Green "Delivered" badge, consistent with the Paid/Shipped badges
      # rendered by Spree::Admin::OrdersHelper#shipment_state.
      def shipment_delivered_badge(shipment)
        return unless shipment.delivered?

        content_tag :span, class: 'badge badge-delivered' do
          icon('check') + Spree.t('shipment_states.delivered')
        end
      end

      # Whether the "Mark as Delivered" button should be shown for a shipment:
      # only once the carrier has it (shipped) and it isn't delivered yet.
      def show_mark_as_delivered?(shipment, order)
        shipment.shipped? &&
          !shipment.delivered? &&
          !order.canceled? &&
          !shipment.canceled?
      end

      # Order-level "Delivered" badge for the admin order header, shown
      # alongside (not instead of) the Shipped badge. An order counts as
      # delivered only when it has shipments and ALL of them are delivered —
      # a partially delivered multi-shipment order must not claim "Delivered"
      # at the top level. (For single-shipment orders, the common case, ANY
      # and ALL coincide.)
      def order_delivered_badge(order)
        shipments = order.shipments.to_a
        return if shipments.empty? || !shipments.all?(&:delivered?)

        shipment_delivered_badge(shipments.max_by(&:delivered_at))
      end
    end
  end
end

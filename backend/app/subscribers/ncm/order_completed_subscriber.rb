# frozen_string_literal: true

module Ncm
  class OrderCompletedSubscriber < Spree::Subscriber
    subscribes_to 'order.completed'

    def handle(event)
      order = find_order(event.payload['id'] || event.payload[:id])
      return unless order && Spree::DeliveryPartner.active.exists?

      order.shipments.each do |shipment|
        next if shipment.ncm_order_id.present?
        next if shipment.order.shipping_address&.district&.ncm_branch.blank?

        Ncm::CreateOrderJob.perform_later(shipment.id)
      end
    end

    private

    def find_order(identifier)
      return if identifier.blank?

      Spree::Order.find_by_prefix_id(identifier) || Spree::Order.find_by(id: identifier)
    end
  end
end
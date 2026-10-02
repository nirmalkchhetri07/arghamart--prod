# frozen_string_literal: true

module Ncm
  # Node equivalent: Solid Queue worker that creates one carrier order.
  class CreateOrderJob < ApplicationJob
    queue_as :default

    def perform(shipment_id)
      shipment = Spree::Shipment.includes(order: :shipping_address).find(shipment_id)

      shipment.with_lock do
        return if shipment.ncm_order_id.present?

        partner = Spree::DeliveryPartner.active.find_by!(provider: 'ncm')
        address = shipment.order.shipping_address
        branch = address&.district&.ncm_branch
        raise ArgumentError, 'Shipment district has no NCM branch mapping' if branch.blank?

        response = Ncm::Client.new(environment: partner.environment, api_token: partner.api_token).create_order(
          name: [address.firstname, address.lastname].compact_blank.join(' '),
          phone: address.phone,
          address: address.full_address,
          fbranch: partner.default_pickup_branch,
          branch: branch,
          cod_charge: shipment.ncm_cod_charge.to_s,
          package: shipment.ncm_package_description,
          vref_id: shipment.order.number,
          delivery_type: 'Door2Door',
          weight: shipment.ncm_weight.to_s,
          instruction: shipment.order.customer_note.to_s
        )

        shipment.update!(ncm_order_id: response.fetch('orderid').to_s, ncm_sent_at: Time.current,
                         ncm_status: 'Pickup Order Created')
      end
    end
  end
end
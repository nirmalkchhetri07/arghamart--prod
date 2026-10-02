# frozen_string_literal: true

# Node equivalent: a background worker that orchestrates a single courier order request.
module Ncm
  class CreateOrderJob < ApplicationJob
    queue_as :default

    def perform(shipment_id)
      shipment = Spree::Shipment.includes(order: :ship_address, inventory_units: { variant: :product }).find(shipment_id)
      order = shipment.order

      order.with_lock do
        order.reload
        return if shipment.ncm_order_id.present? || order.ncm_order_id.present?

        partner = Spree::DeliveryPartner.active.find_by!(provider: 'ncm')
        payload = PayloadBuilder.new(shipment:, partner:).call
        order.ncm_status = 'Sending'
        order.ncm_cod_amount = payload.fetch(:cod_charge)
        order.save!

        response = Client.new(environment: partner.environment, api_token: partner.api_token).create_order(payload)
        order.ncm_order_id = response.fetch('orderid').to_s
        order.ncm_status = response['status'].presence || 'Pickup Order Created'
        order.ncm_sent_at = Time.current
        order.ncm_delivery_charge = shipment.ncm_delivery_charge
        order.save!

        tracking_id = response['trackingid'].presence || response['tracking_id'].presence || response['consignment_id'].presence
        shipment.assign_attributes(
          ncm_order_id: order.ncm_order_id,
          ncm_tracking_id: tracking_id,
          ncm_status: order.ncm_status,
          ncm_sent_at: order.ncm_sent_at,
          ncm_cod_amount: order.ncm_cod_amount,
          tracking: tracking_id.presence || shipment.tracking
        )
        shipment.save!
      end
    rescue Ncm::PayloadBuilder::ValidationError => e
      raise ArgumentError, 'no NCM branch mapping for this shipping address' if e.message.to_s.match?(/branch|district|province|address/i)

      raise
    rescue StandardError => e
      record_failure(shipment, e) if shipment
      raise
    end

    private

    def record_failure(shipment, error)
      shipment.update_columns(
        ncm_status: 'Needs delivery review',
        ncm_review_reason: error.message,
        ncm_failure_message: error.message,
        updated_at: Time.current
      )
      shipment.order.update_columns(ncm_status: 'Needs delivery review', updated_at: Time.current)
    end
  end
end
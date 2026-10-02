# frozen_string_literal: true

module Spree
  class ShipmentMailer < BaseMailer
    def delivered(shipment_id)
      @shipment = Spree::Shipment.includes(:order).find(shipment_id)
      @order = @shipment.order
      @current_store = @order.store

      return if @order.email.blank?

      with_store_locale(@current_store) do
        mail(
          to: @order.email,
          subject: Spree.t('shipment_mailer.delivered.subject',
                           store: @current_store.name,
                           number: @order.number),
          store_url: @current_store.formatted_url
        )
      end
    end
  end
end
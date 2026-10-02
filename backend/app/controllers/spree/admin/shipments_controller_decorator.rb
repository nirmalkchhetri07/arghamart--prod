# frozen_string_literal: true

# Adds the "Mark as Delivered" admin action for shipments. Layers delivery
# tracking on top of the shipment state machine without touching its states —
# see Spree::ShipmentDecorator. Structure mirrors the gem's own #ship action.
module Spree
  module Admin
    module ShipmentsControllerDecorator
      # POST /admin/orders/:order_id/shipments/:id/mark_as_delivered
      def mark_as_delivered
        if @shipment.delivered?
          flash[:notice] = Spree.t(:shipment_already_delivered)
        elsif @shipment.shipped? && @shipment.mark_as_delivered!
          flash[:success] = Spree.t(:shipment_successfully_delivered)
        else
          flash[:error] = Spree.t(:cannot_mark_as_delivered)
        end

        redirect_back fallback_location: spree.edit_admin_order_path(@order)
      end

      # POST /admin/orders/:order_id/shipments/:id/send_to_ncm
      def send_to_ncm
        if @shipment.ncm_order_id.present?
          flash[:notice] = Spree.t('admin.ncm.already_sent')
        elsif Spree::DeliveryPartner.active.find_by(provider: 'ncm').blank?
          flash[:error] = Spree.t('admin.ncm.not_configured')
        elsif @shipment.order.shipping_address&.district&.ncm_branch.blank?
          flash[:error] = Spree.t('admin.ncm.branch_missing')
        else
          Ncm::CreateOrderJob.perform_later(@shipment.id)
          flash[:success] = Spree.t('admin.ncm.queued')
        end

        redirect_back fallback_location: spree.edit_admin_order_path(@order)
      end
    end

    ShipmentsController.prepend ShipmentsControllerDecorator
  end
end

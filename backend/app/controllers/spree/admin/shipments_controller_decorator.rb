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
    end

    ShipmentsController.prepend ShipmentsControllerDecorator
  end
end

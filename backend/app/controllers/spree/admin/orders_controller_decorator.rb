# frozen_string_literal: true

# Spree 5.6 looks admin orders up by Stripe-style prefixed ID
# (e.g. /admin/orders/or_VqXmZF31wY), while staff still refer to orders by
# their human-readable legacy number (e.g. R672084530, shown in the UI).
# Hitting the detail page with the legacy number raises RecordNotFound and
# lands on the orders index, which looks like the page "doesn't render".
#
# This bridges the two: on RecordNotFound, retry the lookup by legacy
# number within the current store and redirect to the canonical prefixed
# URL when it matches. Anything else falls through to Spree's stock
# not-found handling (redirect to the orders index with an error flash).
module Spree
  module Admin
    module OrdersControllerDecorator
      def self.prepended(base)
        base.rescue_from ActiveRecord::RecordNotFound, with: :redirect_legacy_order_number
      end

      private

      def redirect_legacy_order_number
        order = params[:id].present? && current_store.orders.find_by(number: params[:id])

        if order
          redirect_to spree.admin_order_path(order)
        else
          resource_not_found
        end
      end
    end

    OrdersController.prepend OrdersControllerDecorator
  end
end

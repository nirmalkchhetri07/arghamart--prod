# frozen_string_literal: true

# Permits the Manual QR image upload on the admin payment-method form (see
# app/views/spree/admin/payment_methods/custom_form_fields/_manual_qr).
module Spree
  module Admin
    module PaymentMethodsControllerDecorator
      private

      def permitted_resource_params
        params.require(:payment_method).permit(
          permitted_payment_method_attributes +
            @object.preferences.keys.map { |key| "preferred_#{key}" } +
            [:qr_image]
        )
      end
    end
  end
end

Spree::Admin::PaymentMethodsController.prepend Spree::Admin::PaymentMethodsControllerDecorator

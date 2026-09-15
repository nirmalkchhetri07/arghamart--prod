# frozen_string_literal: true

module Spree
  module PaymentSessions
    # STI subclass for eSewa (see Spree::PaymentMethod::Esewa).
    # Uses the `spree_payment_sessions` table; `external_id` is the eSewa
    # `transaction_uuid`, `external_data` carries the signed form fields.
    class Esewa < Spree::PaymentSession
      def transaction_uuid
        external_id
      end

      def form_url
        external_data&.dig('form_url')
      end

      # Alias: the storefront redirects (auto-POSTs) the customer here.
      def redirect_url
        form_url
      end

      def form_fields
        external_data&.dig('form_fields') || {}
      end

      def signature
        external_data&.dig('signature')
      end
    end
  end
end

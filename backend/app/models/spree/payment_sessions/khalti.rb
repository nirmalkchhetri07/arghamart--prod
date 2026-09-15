# frozen_string_literal: true

module Spree
  module PaymentSessions
    # STI subclass for Khalti (see Spree::PaymentMethod::Khalti).
    # Uses the `spree_payment_sessions` table; `external_id` is the Khalti
    # `pidx`, `external_data` carries `payment_url` + lookup metadata.
    class Khalti < Spree::PaymentSession
      def pidx
        external_id
      end

      def payment_url
        external_data&.dig('payment_url')
      end
    end
  end
end

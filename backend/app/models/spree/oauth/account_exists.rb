# frozen_string_literal: true

module Spree
  module Oauth
    # The provider email is unverified and already belongs to a Spree user.
    # Carries the verified identity payload so the controller can mint a
    # short-lived pending token: the identity links only after the customer
    # proves ownership with their password.
    class AccountExists < Error
      attr_reader :payload

      def initialize(message = 'An account with this email already exists', payload = {})
        @payload = payload
        super(message)
      end
    end
  end
end

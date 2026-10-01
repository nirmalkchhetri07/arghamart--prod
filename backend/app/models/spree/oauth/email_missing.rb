# frozen_string_literal: true

module Spree
  module Oauth
    # The provider gave no email address for a login without a linked
    # identity. Carries the verified identity payload so the controller can
    # mint a short-lived pending token and ask the customer for an email.
    class EmailMissing < Error
      attr_reader :payload

      def initialize(message = 'Email address is missing', payload = {})
        @payload = payload
        super(message)
      end
    end
  end
end

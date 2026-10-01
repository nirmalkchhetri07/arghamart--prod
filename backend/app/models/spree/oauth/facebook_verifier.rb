# frozen_string_literal: true

# Placeholder for a future Facebook (authorization-code) verifier, which
# will exchange the code with the record's client_secret server-side.
module Spree
  module Oauth
    class FacebookVerifier
      def self.verify(_credential, _provider_record)
        raise NotImplementedError, 'Facebook login is not implemented yet'
      end
    end
  end
end

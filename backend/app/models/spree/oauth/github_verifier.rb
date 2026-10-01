# frozen_string_literal: true

# Placeholder for a future GitHub (authorization-code) verifier, which will
# exchange the code with the record's client_secret server-side.
module Spree
  module Oauth
    class GithubVerifier
      def self.verify(_credential, _provider_record)
        raise NotImplementedError, 'GitHub login is not implemented yet'
      end
    end
  end
end

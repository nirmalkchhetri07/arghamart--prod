# frozen_string_literal: true

# Social-login base error. Raised by verifiers and the login service,
# rescued by the Store API OAuth controller into public error codes.
# Messages never include credentials.
module Spree
  module Oauth
    class Error < StandardError; end
  end
end

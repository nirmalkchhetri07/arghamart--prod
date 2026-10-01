# frozen_string_literal: true

module Spree
  module Oauth
    # The verified email is not confirmed at the provider — refuse login.
    class EmailNotVerified < Error; end
  end
end

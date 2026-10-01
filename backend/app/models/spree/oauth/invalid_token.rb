# frozen_string_literal: true

module Spree
  module Oauth
    # The credential failed verification (bad signature, wrong audience,
    # expired, unknown/disabled provider, …).
    class InvalidToken < Error; end
  end
end

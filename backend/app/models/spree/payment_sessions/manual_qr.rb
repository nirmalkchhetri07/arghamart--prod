# frozen_string_literal: true

module Spree
  module PaymentSessions
    # Manual QR redirect-less session. The screenshot proof is attached here
    # first (the Spree::Payment doesn't exist yet at upload time) and moved
    # onto the payment when the session completes.
    class ManualQr < Spree::PaymentSession
      has_one_attached :proof_image

      validates :proof_image,
                content_type: Spree::PaymentMethod::ManualQr::PROOF_CONTENT_TYPES,
                size: { less_than: Spree::PaymentMethod::ManualQr::PROOF_MAX_BYTES },
                if: -> { proof_image.attached? }
    end
  end
end

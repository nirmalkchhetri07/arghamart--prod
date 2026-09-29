# frozen_string_literal: true

# Manual QR proof attachment + review status for Spree::Payment.
#
# Verification state is derived from the payment state machine — no extra
# status column that could drift:
#   pending            → awaiting admin review
#   completed          → verified by an admin (Approve)
#   void / failed      → rejected by an admin (Reject), with the reason in
#                        `qr_rejection_reason`
module Spree
  module PaymentDecorator
    def self.prepended(base)
      base.has_one_attached :proof_image

      base.validates :proof_image,
                     content_type: Spree::PaymentMethod::ManualQr::PROOF_CONTENT_TYPES,
                     size: { less_than: Spree::PaymentMethod::ManualQr::PROOF_MAX_BYTES },
                     if: -> { proof_image.attached? }
    end

    # True for payments taken via the Manual QR method (STI-safe: also true
    # when the method was soft-deleted, via `with_deleted`).
    def manual_qr?
      payment_method_id.present? &&
        Spree::PaymentMethod.with_deleted.where(
          id: payment_method_id, type: Spree::PaymentMethod::ManualQr.sti_name
        ).exists?
    end

    # Customer-facing verification status for Manual QR payments.
    # Returns nil for every other payment method.
    #
    # @return ["pending", "verified", "rejected", nil]
    def qr_status
      return nil unless manual_qr?

      case state.to_s
      when 'completed' then 'verified'
      when 'void', 'failed', 'invalid' then 'rejected'
      else 'pending'
      end
    end
  end

  Payment.prepend PaymentDecorator
end

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

    # ── Admin review checks (rendered on the payment card) ────────────────

    # How many *other* payments on this store carry the same customer-supplied
    # transaction ID. A reused ID usually means someone filed a proof that
    # isn't theirs (or the same payment was submitted for two orders).
    #
    # @return [Integer]
    def qr_transaction_id_duplicate_count
      return 0 if id.nil? || qr_transaction_id.blank?

      qr_sibling_payments.where(qr_transaction_id: qr_transaction_id).count
    end

    # How many *other* payments on this store hold a byte-identical screenshot
    # (same Active Storage checksum) — the same proof image filed twice.
    #
    # @return [Integer]
    def qr_proof_duplicate_count
      return 0 if id.nil? || !proof_image.attached? || proof_image.blob.nil?

      qr_sibling_payments.
        joins(proof_image_attachment: :blob).
        where(active_storage_blobs: { checksum: proof_image.blob.checksum }).
        count
    end

    # True while the payment is awaiting review and its amount differs from
    # what the order still owes — the screenshot can't be trusted at face
    # value. Only meaningful pre-approval (once completed, amount due drops
    # to 0 by definition).
    #
    # @return [Boolean]
    def qr_amount_mismatch?
      return false unless manual_qr? && pending? && order.present?

      amount.to_d != order.amount_due.to_d
    end

    # Absolute admin URL for reviewing this payment's order. Built outside a
    # request (alert email/webhook), so the host comes from the explicit
    # `admin_url` preference, else the routing defaults (RAILS_HOST in
    # production), else the store URL (localhost in development).
    #
    # @return [String, nil]
    def qr_admin_review_url
      return nil if order.nil?

      if Spree::Config[:admin_url].present?
        base = Spree::Config[:admin_url]
        base = "https://#{base}" unless base.match?(%r{\Ahttps?://}i)
        return "#{base.chomp('/')}#{Spree.admin_path}/orders/#{order.to_param}"
      end

      routing = Rails.application.routes.default_url_options
      if routing[:host].present?
        return Spree::Core::Engine.routes.url_helpers.admin_order_url(order, **routing)
      end

      base = order.store&.formatted_url
      return nil if base.blank?

      "#{base.chomp('/')}#{Spree.admin_path}/orders/#{order.to_param}"
    end

    private

    # Duplicate checks are scoped to the store: the same screenshot or
    # transaction ID on another tenant's order is not this reviewer's problem.
    def qr_sibling_payments
      Spree::Payment.
        where.not(id: id).
        joins(:order).
        where(spree_orders: { store_id: order.store_id })
    end
  end

  Payment.prepend PaymentDecorator
end

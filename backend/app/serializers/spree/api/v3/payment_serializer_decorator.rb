# frozen_string_literal: true

# Exposes Manual QR review data on the Store API payment payloads (embedded in
# cart/order responses) so the storefront can show the proof image and the
# verification status on the customer's order page — and offer a re-upload
# when the proof was rejected.
#
# `proof_url` points at the authorized proof endpoint (owner token or customer
# JWT required), never at a raw blob URL, so proofs stay visible only to the
# order owner. Non-QR payments serialize these attributes as null.
module Spree
  module Api
    module V3
      module PaymentSerializerDecorator
        def self.prepended(base)
          base.typelize qr_status: [:string, { nullable: true }],
                         qr_transaction_id: [:string, { nullable: true }],
                         qr_rejection_reason: [:string, { nullable: true }],
                         proof_url: [:string, { nullable: true }]

          base.attribute :qr_status do |payment|
            payment.try(:qr_status)
          end

          base.attribute :qr_transaction_id do |payment|
            payment.try(:qr_transaction_id)
          end

          base.attribute :qr_rejection_reason do |payment|
            payment.try(:qr_rejection_reason)
          end

          base.attribute :proof_url do |payment|
            next nil unless payment.try(:manual_qr?) && payment.proof_image.attached?

            order = payment.order
            next nil if order.blank?

            "/api/v3/store/orders/#{order.prefixed_id}/payments/#{payment.prefixed_id}/proof"
          end
        end
      end

      PaymentSerializer.prepend PaymentSerializerDecorator
    end
  end
end

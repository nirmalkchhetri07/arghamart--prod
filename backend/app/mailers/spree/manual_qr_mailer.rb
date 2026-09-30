# frozen_string_literal: true

module Spree
  # Admin alert: a Manual QR proof is waiting for review.
  #
  # Sent by Spree::ManualQrAlertJob (queued from
  # Spree::PaymentMethod::ManualQr#complete_payment_session) so a proof never
  # sits unreviewed while customers wait. Recipients are the method's
  # `alert_emails` preference or, when blank, the store's staff.
  class ManualQrMailer < BaseMailer
    # @param payment_id [Integer] the pending Spree::Payment to review
    # @param recipients [Array<String>, nil] explicit to: list. Pass `[]` for
    #   "nobody"; nil falls back to the method's #alert_recipients
    def proof_uploaded(payment_id, recipients = nil)
      @payment = Spree::Payment.find(payment_id)
      @order = @payment.order
      @current_store = @order.store
      @payment_method = @payment.payment_method ||
                        Spree::PaymentMethod.with_deleted.find_by(id: @payment.payment_method_id)

      recipients = recipients.nil? ? (@payment_method.try(:alert_recipients) || []) : Array(recipients)
      return if recipients.blank?

      with_store_locale(@current_store) do
        mail(
          to: recipients,
          subject: Spree.t('manual_qr_mailer.proof_uploaded.subject',
                           store: @current_store.name,
                           number: @order.number),
          store_url: @current_store.formatted_url
        )
      end
    end
  end
end

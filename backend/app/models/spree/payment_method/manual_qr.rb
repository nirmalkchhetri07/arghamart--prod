# frozen_string_literal: true

# Manual QR payment method (pay in your own banking/wallet app, upload proof).
#
# Admin setup (Settings > Payments, no code needed beyond this file):
#   1. New payment method of type "ManualQr", front_end, active.
#   2. Upload the store's QR image (custom field below the preferences) and
#      enter the payment instructions (e.g. account name/number, "send exactly
#      the order total and upload the screenshot here").
#
# Flow:
#   1. Storefront creates a PaymentSession via the Store API. We return the
#      public QR image path, the instructions and the amount in `external_data`
#      — no secrets are involved, so nothing needs hiding from the serializer.
#   2. Customer pays externally, then uploads a screenshot (+ optional
#      transaction ID) to the proof endpoint, which attaches it to the session.
#   3. Storefront calls paymentSessions.complete. We require the proof, create
#      the Spree::Payment, move the proof onto it and leave it `pending`.
#      The order completes with payment_state `balance_due`, like COD.
#   4. An admin reviews the proof on the order page and Approves (completes the
#      payment) or Rejects (voids it with a reason). A rejected payment can be
#      replaced by uploading a new proof, which creates a fresh pending payment
#      — the voided one stays as history.
#
# Admin-side guard rails (all configured per method, no code needed):
#   * `alert_emails` / `alert_webhook_url` — notify the admin the moment a
#     proof becomes reviewable (Spree::ManualQrAlertJob → email + optional
#     JSON webhook for Slack/n8n → Telegram/WhatsApp relays).
#   * `order_timeout_hours` — cancel QR orders nobody verified in time and
#     release their stock (Spree::ManualQrExpireOrdersJob, recurring).
#
# Multiple methods are first-class: create one ManualQr method per QR option
# ("Fonepay QR", "Bank QR", "eSewa wallet QR", …) and each shows up at
# checkout as its own choice with its own QR image and instructions.
module Spree
  class PaymentMethod::ManualQr < Spree::PaymentMethod
    # Screenshot content types we accept as proof (also enforced server-side
    # on upload — the storefront file picker mirrors this list).
    PROOF_CONTENT_TYPES = %w[image/png image/jpeg image/webp].freeze
    PROOF_MAX_BYTES = 5.megabytes.freeze

    has_one_attached :qr_image

    validates :qr_image,
              content_type: PROOF_CONTENT_TYPES,
              size: { less_than: PROOF_MAX_BYTES },
              if: -> { qr_image.attached? }

    preference :instructions, :text, default: ''

    # ── Admin alerts ─────────────────────────────────────────────────────
    # Who hears about a freshly uploaded proof (Spree::ManualQrAlertJob).
    # `alert_emails`: comma-separated addresses; blank → every staff member
    # with a role on this method's store.
    preference :alert_emails, :string, default: ''
    # `alert_webhook_url`: optional HTTP endpoint posted a JSON body with a
    # Slack-style `text` plus structured fields — n8n/Make/Zapier → Telegram
    # or WhatsApp, or `api.telegram.org/bot<TOKEN>/sendMessage?chat_id=…`
    # (posted form-encoded, chat_id rides in the query string).
    preference :alert_webhook_url, :string, default: ''

    # ── Order timeout ────────────────────────────────────────────────────
    # Hours after completion during which the QR payment must be verified by
    # an admin. Past that, Spree::ManualQrExpireOrdersJob cancels the order
    # and releases its stock. 0 (or less) disables the timeout.
    preference :order_timeout_hours, :integer, default: 24

    # Alert recipients: the configured list, or — when that is blank — every
    # staff member with a role on this method's store.
    #
    # @return [Array<String>] emails, possibly empty (nothing to send)
    def alert_recipients
      configured = preferred_alert_emails.to_s.split(',').map(&:strip).reject(&:empty?)
      return configured if configured.any?

      store_staff_emails
    end

    def session_required?
      true
    end

    def source_required?
      false
    end

    def payment_session_class
      Spree::PaymentSessions::ManualQr
    end

    # Renders the QR upload fieldset on the admin payment-method form (see
    # app/views/spree/admin/payment_methods/custom_form_fields/_manual_qr).
    def custom_form_fields_partial_name
      'manual_qr'
    end

    # Manual QR only makes sense where the store prices in NPR — hide it from
    # foreign-currency orders instead of quoting an amount the QR can't match.
    def available_for_order?(order)
      super && order.currency == 'NPR'
    end

    # ── Gateway-style no-ops ─────────────────────────────────────────────
    # Money never moves through us: the customer pays in their own banking
    # app and an admin verifies the screenshot. Spree's cancel path
    # (Spree::Order#after_cancel → Payment#void_transaction!) still calls
    # `void` on every incomplete payment, so answering "success, nothing to
    # do" keeps auto-cancellation (Spree::ManualQrExpireOrdersJob) and the
    # admin Reject flow from blowing up on a missing gateway method.
    def actions
      %w{void}
    end

    def can_void?(payment)
      payment.state != 'void'
    end

    def void(*)
      simulated_successful_billing_response
    end

    def cancel(*)
      simulated_successful_billing_response
    end

    def credit(*)
      simulated_successful_billing_response
    end

    # No gateway behind Manual QR — the void above is the whole story.
    def simulated_successful_billing_response
      Spree::PaymentResponse.new(true, '', {}, {})
    end

    # Storefront passes nothing extra on create; the QR payload below is the
    # whole point of the session. Amount defaults to the order balance.
    def create_payment_session(order:, amount: nil, external_data: {})
      total = amount.presence || order.total_minus_store_credits

      # NOTE: create via payment_session_class (not the `payment_sessions`
      # association) so the STI `type` column is populated — the base-class
      # association would insert type=NULL and violate the NOT NULL constraint.
      payment_session_class.create!(
        order: order,
        payment_method: self,
        amount: total,
        currency: order.currency,
        external_id: SecureRandom.uuid,
        external_data: {
          'qr_image_url' => qr_image_url,
          'instructions' => preferred_instructions.to_s,
          'amount' => total.to_s,
          'currency' => order.currency
        }.compact,
        customer: order.try(:customer) || order.try(:user)
      )
    end

    # The QR amount is derived from the order, so only re-sync the amount and
    # merge any extra data — same shape as the eSewa/Khalti implementations.
    def update_payment_session(payment_session:, amount: nil, external_data: {})
      attrs = {}
      attrs[:amount] = amount if amount.present?

      if external_data.present?
        attrs[:external_data] = (payment_session.external_data || {}).merge(indifferent_params(external_data))
      end

      payment_session.update!(attrs) if attrs.any?
      payment_session
    end

    # The transaction ID arrives nested (`external_data[transaction_id]`) —
    # the Store API complete endpoint only permits `session_result` plus an
    # `external_data` hash, and the screenshot itself travels via the separate
    # proof-upload endpoint (multipart can't ride along as JSON).
    #
    # The payment is deliberately left `pending`: money movement was claimed
    # by the customer, not observed. An admin completes it after reviewing
    # the screenshot (Approve) or voids it (Reject).
    def complete_payment_session(payment_session:, params: {})
      params = indifferent_params(params)
      transaction_id = params[:transaction_id].presence ||
                       params.dig(:external_data, :transaction_id).presence

      unless payment_session.proof_image.attached?
        payment_session.errors.add(:base, :manual_qr_proof_missing)
        payment_session.fail! if payment_session.respond_to?(:can_fail?) ? payment_session.can_fail? : true
        return payment_session
      end

      payment_session.process! if payment_session.respond_to?(:can_process?) ? payment_session.can_process? : true

      payment = payment_session.find_or_create_payment!

      if payment.present?
        payment.proof_image.attach(payment_session.proof_image.blob) unless payment.proof_image.attached?
        payment.update!(qr_transaction_id: transaction_id) if transaction_id.present?

        was_pending = payment.pending?
        payment.pend! if payment.respond_to?(:can_pend?) ? payment.can_pend? : true

        # The proof just became reviewable for the first time → tell the admin
        # (email + optional webhook). Re-completing an already-pending session
        # stays silent.
        Spree::ManualQrAlertJob.perform_later(payment.id) if !was_pending && payment.pending?
      end

      payment_session.complete! unless payment_session.completed?
      payment_session
    rescue ActiveRecord::RecordInvalid => e
      payment_session.errors.add(:base, e.message)
      payment_session.fail! if payment_session.respond_to?(:can_fail?) ? payment_session.can_fail? : true
      payment_session
    end

    private

    # Staff addresses for the blank-`alert_emails` fallback: every user with a
    # role assignment on this method's store (same query the admin dashboard
    # uses to list a store's staff). Verified against the store, because
    # RoleUser's `resource` is polymorphic.
    def store_staff_emails
      Spree.admin_user_class.
        joins(:role_users).
        where(Spree::RoleUser.table_name => { resource: store }).
        distinct.
        pluck(:email).
        compact
    end

    # Public path (not a signed URL): the store QR is identical for every
    # customer, so it needs no authorization. The storefront prefixes it with
    # the API host, which next.config already allow-lists for Active Storage.
    # Returns nil when no QR is configured — the storefront then shows the
    # instructions with a "QR unavailable, contact support" fallback.
    def qr_image_url
      return nil unless qr_image.attached?

      Rails.application.routes.url_helpers.rails_blob_path(qr_image, only_path: true)
    end

    # The Store API hands us ActionController::Parameters (not a Hash) for
    # external_data/params — normalize without assuming Hash.
    def indifferent_params(value)
      case value
      when ActionController::Parameters then value.to_unsafe_h.with_indifferent_access
      when Hash then value.with_indifferent_access
      else {}.with_indifferent_access
      end
    end
  end
end

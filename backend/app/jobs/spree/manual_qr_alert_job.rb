# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module Spree
  # Tells the admin that a Manual QR proof is waiting for review — enqueued by
  # Spree::PaymentMethod::ManualQr#complete_payment_session the moment a proof
  # becomes a pending payment (checkout completion and post-rejection re-upload
  # both funnel through it), so nothing sits unreviewed in silence.
  #
  # Two independent channels, both configured on the payment method:
  #
  #   * Email — `preferred_alert_emails` (comma-separated), falling back to
  #     every staff member with a role on the method's store. A failure here
  #     propagates: the job is recorded as failed and shows up in the /jobs
  #     dashboard for a retry, because silently losing the primary channel
  #     is worse than a visible error.
  #
  #   * Webhook — `preferred_alert_webhook_url`, optional and best-effort
  #     (errors are logged, never raised, so a dead relay can't shadow the
  #     email). Posts JSON with a Slack-compatible `text` plus structured
  #     fields, which n8n/Make/Zapier → Telegram or WhatsApp relays consume
  #     as-is. For Telegram directly, point the URL at
  #     `https://api.telegram.org/bot<TOKEN>/sendMessage?chat_id=<id>`: that
  #     host is special-cased to post form-encoded (`text` is a native
  #     Telegram field, `chat_id` rides in the query string).
  class ManualQrAlertJob < Spree::BaseJob
    WEBHOOK_OPEN_TIMEOUT = 5
    WEBHOOK_READ_TIMEOUT = 10

    def perform(payment_id)
      payment = Spree::Payment.find(payment_id)
      return unless payment.manual_qr? && payment.pending?

      method = payment_method_for(payment)
      return if method.nil?

      deliver_email(payment, method)
      deliver_webhook(payment, method)
    end

    private

    # The method may have been soft-deleted since the payment was created —
    # `Spree::Payment#payment_method` then returns nil, but its alert
    # preferences are still exactly what the admin configured.
    def payment_method_for(payment)
      payment.payment_method ||
        Spree::PaymentMethod.with_deleted.find_by(id: payment.payment_method_id)
    end

    def deliver_email(payment, method)
      recipients = method.alert_recipients
      return if recipients.empty?

      Spree::ManualQrMailer.proof_uploaded(payment.id, recipients).deliver_now
    end

    def deliver_webhook(payment, method)
      url = method.preferred_alert_webhook_url.to_s.strip
      return if url.blank?

      uri = parse_webhook_uri(url)
      return if uri.nil?

      response = post_webhook(uri, alert_payload(payment, method))
      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("[manual_qr] alert webhook #{uri.host} responded #{response.code}")
      end
    rescue StandardError => e
      Rails.logger.warn("[manual_qr] alert webhook failed: #{e.class}: #{e.message}")
    end

    def parse_webhook_uri(url)
      uri = URI.parse(url)
      unless uri.is_a?(URI::HTTP) # rejects ftp://, file://, javascript: …
        Rails.logger.warn("[manual_qr] alert webhook URL is not http(s), ignored")
        return nil
      end

      uri
    rescue URI::InvalidURIError
      Rails.logger.warn('[manual_qr] alert webhook URL is not a valid URI, ignored')
      nil
    end

    def post_webhook(uri, payload)
      request = if uri.host == 'api.telegram.org'
                  Net::HTTP::Post.new(uri.request_uri).tap do |req|
                    req.set_form_data('text' => payload[:text].to_s)
                  end
                else
                  Net::HTTP::Post.new(uri.request_uri).tap do |req|
                    req.body = JSON.generate(payload)
                    req['Content-Type'] = 'application/json'
                  end
                end

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = WEBHOOK_OPEN_TIMEOUT
      http.read_timeout = WEBHOOK_READ_TIMEOUT
      http.request(request)
    end

    def alert_payload(payment, method)
      order = payment.order

      {
        event: 'manual_qr.proof_uploaded',
        text: Spree.t('manual_qr.alert_text',
                      store: order.store.name,
                      number: order.number,
                      amount: payment.display_amount.to_s,
                      method: method.name),
        order_number: order.number,
        order_id: order.to_param,
        payment_number: payment.number,
        payment_method: method.name,
        amount: payment.amount.to_s,
        amount_due: order.amount_due.to_s,
        display_amount: payment.display_amount.to_s,
        currency: order.currency,
        transaction_id: payment.qr_transaction_id,
        received_at: payment.created_at.iso8601,
        admin_url: payment.qr_admin_review_url
      }.compact
    end
  end
end

# frozen_string_literal: true

# eSewa ePay v2 gateway (redirect + server-side verify, no webhooks).
#
# Flow (see https://developer.esewa.com.np/pages/Epay-V2):
#   1. Storefront creates a PaymentSession via the Store API.
#      We generate a `transaction_uuid`, build the eSewa form fields and
#      HMAC-SHA256 signature, and return them in `external_data` so the
#      storefront can auto-POST the customer to eSewa.
#   2. Customer pays on eSewa, eSewa redirects back to the storefront's
#      success_url / failure_url with `?data=<base64 JSON>`.
#   3. Storefront calls paymentSessions.complete. We IGNORE the client-supplied
#      `data` for the verdict and call eSewa's status-check endpoint
#      server-to-server, only completing when `status == "COMPLETE"`.
#
# Test credentials (sandbox / UAT only, from eSewa docs + Esewa_payment_nodejs):
#   product_code: EPAYTEST
#   secret_key:   8gBm/:&EnhH.1/q
#   eSewa test IDs: 9806800001..9806800005 / Password Nepal@123 / Token 123456 / MPIN 1122
#
# Credentials live in Spree preferences (admin UI: Settings > Payments),
# never hardcoded. `secret_key` uses the `:password` type so the admin UI
# masks it. Treat DB dumps as containing live secrets.
module Spree
  class PaymentMethod::Esewa < Spree::PaymentMethod
    SIGNED_FIELD_NAMES = 'total_amount,transaction_uuid,product_code'

    SANDBOX_FORM_URL = 'https://rc-epay.esewa.com.np/api/epay/main/v2/form'
    PRODUCTION_FORM_URL = 'https://epay.esewa.com.np/api/epay/main/v2/form'

    SANDBOX_STATUS_URL = 'https://rc.esewa.com.np/api/epay/transaction/status/'
    PRODUCTION_STATUS_URL = 'https://esewa.com.np/api/epay/transaction/status/'

    preference :product_code, :string
    preference :secret_key, :password
    preference :env, :string, default: 'sandbox' # sandbox | production

    def payment_icon_name
      'esewa'
    end

    def session_required?
      true
    end

    def source_required?
      false
    end

    def payment_session_class
      Spree::PaymentSessions::Esewa
    end

    def sandbox?
      preferred_env.to_s != 'production'
    end

    def form_endpoint_url
      sandbox? ? SANDBOX_FORM_URL : PRODUCTION_FORM_URL
    end

    def status_check_base_url
      sandbox? ? SANDBOX_STATUS_URL : PRODUCTION_STATUS_URL
    end

    # HMAC-SHA256 over "total_amount=X,transaction_uuid=Y,product_code=Z",
    # Base64-encoded (strict, no newlines). Field order and no-spaces matter.
    def generate_signature(total_amount:, transaction_uuid:, product_code: nil)
      code = product_code || preferred_product_code
      message = "total_amount=#{total_amount},transaction_uuid=#{transaction_uuid},product_code=#{code}"
      raw = OpenSSL::HMAC.digest('sha256', preferred_secret_key.to_s, message)
      Base64.strict_encode64(raw)
    end

    # eSewa amounts are plain decimal strings ("100", "100.50").
    # Normalizes BigDecimal/Float/Integer to a canonical string so the
    # signature and the status-check query always agree.
    def format_esewa_amount(value)
      str = format('%.2f', BigDecimal(value.to_s))
      str.sub(/\.00$/, '').sub(/(\.\d)0$/, '\1')
    end

    # Storefront passes redirect targets in `external_data`:
    #   { success_url: "...", failure_url: "..." } (or a single `return_url`).
    def create_payment_session(order:, amount: nil, external_data: {})
      total = amount.presence || order.total_minus_store_credits
      total_str = format_esewa_amount(total)
      transaction_uuid = SecureRandom.uuid
      code = preferred_product_code

      data = indifferent_params(external_data)
      success_url = data[:success_url] || data[:return_url]
      failure_url = data[:failure_url] || data[:return_url]

      signature = generate_signature(total_amount: total_str, transaction_uuid: transaction_uuid, product_code: code)

      form_fields = {
        'amount' => total_str,
        'tax_amount' => '0',
        'total_amount' => total_str,
        'transaction_uuid' => transaction_uuid,
        'product_code' => code,
        'product_service_charge' => '0',
        'product_delivery_charge' => '0',
        'success_url' => success_url.to_s,
        'failure_url' => failure_url.to_s,
        'signed_field_names' => SIGNED_FIELD_NAMES,
        'signature' => signature
      }

      # NOTE: create via payment_session_class (not the `payment_sessions`
      # association) so the STI `type` column is populated — the base-class
      # association would insert type=NULL and violate the NOT NULL constraint.
      payment_session_class.create!(
        order: order,
        payment_method: self,
        amount: total,
        currency: order.currency,
        external_id: transaction_uuid,
        external_data: {
          'form_url' => form_endpoint_url,
          'form_fields' => form_fields,
          'transaction_uuid' => transaction_uuid,
          'product_code' => code,
          'total_amount' => total_str,
          'signed_field_names' => SIGNED_FIELD_NAMES,
          'signature' => signature,
          'success_url' => success_url.to_s,
          'failure_url' => failure_url.to_s
        }.compact,
        customer: order.try(:customer) || order.try(:user)
      )
    end

    # eSewa has no server-side session to update — regenerate the signature
    # if the amount changed so a stale form can't be reused.
    def update_payment_session(payment_session:, amount: nil, external_data: {})
      attrs = {}

      if amount.present? && BigDecimal(amount.to_s) != BigDecimal(payment_session.amount.to_s)
        total_str = format_esewa_amount(amount)
        signature = generate_signature(
          total_amount: total_str,
          transaction_uuid: payment_session.external_id,
          product_code: preferred_product_code
        )
        merged = (payment_session.external_data || {}).merge(
          'total_amount' => total_str,
          'signature' => signature,
          'form_fields' => ((payment_session.external_data || {})['form_fields'] || {}).merge(
            'amount' => total_str,
            'total_amount' => total_str,
            'signature' => signature
          )
        )
        attrs[:amount] = amount
        attrs[:external_data] = merged
      end

      if external_data.present?
        merged_data = (attrs[:external_data] || payment_session.external_data || {}).merge(indifferent_params(external_data))
        attrs[:external_data] = merged_data
      end

      payment_session.update!(attrs) if attrs.any?
      payment_session
    end

    # Verify server-to-server via the status-check endpoint. Never trust the
    # client-supplied `data` param alone — it is decoded for logging only.
    #
    # The redirect payload can arrive top-level (`params[:data]`, direct calls)
    # or nested under `params[:external_data][:data]` (Store API complete
    # endpoint, which nests provider data under `external_data`).
    # The verdict always comes from GET
    # {status_url}?product_code=X&total_amount=Y&transaction_uuid=Z
    # returning { "status": "COMPLETE", ... }.
    def complete_payment_session(payment_session:, params: {})
      params = indifferent_params(params)
      redirect_data = params[:data].presence ||
                      params.dig(:external_data, :data).presence ||
                      params.dig('external_data', 'data').presence

      # Decode the redirect payload for diagnostics only — not for the verdict.
      if redirect_data.present?
        begin
          decoded = JSON.parse(Base64.strict_decode64(redirect_data.to_s))
          Rails.logger.info("[Esewa] redirect payload for #{payment_session.external_id}: #{decoded.slice('status', 'transaction_code', 'total_amount').inspect}")
        rescue StandardError => e
          Rails.logger.warn("[Esewa] could not decode redirect data: #{e.message}")
        end
      end

      expected_total = format_esewa_amount(payment_session.amount)
      result = verify_transaction(
        transaction_uuid: payment_session.external_id,
        total_amount: expected_total,
        product_code: preferred_product_code
      )

      status = result['status'].to_s
      returned_total = result['total_amount'] || result['totalAmount']

      amounts_match = returned_total.nil? || BigDecimal(returned_total.to_s) == BigDecimal(payment_session.amount.to_s)

      if status == 'COMPLETE' && amounts_match
        payment_session.process! if payment_session.respond_to?(:can_process?) ? payment_session.can_process? : true

        payment = payment_session.find_or_create_payment!

        if payment.present? && !payment.completed?
          payment.started_processing! if payment.checkout?
          payment.complete! if payment.can_complete?
        end

        payment_session.complete! unless payment_session.completed?
      else
        Rails.logger.warn(
          "[Esewa] verification failed for #{payment_session.external_id}: " \
          "status=#{status.inspect} amounts_match=#{amounts_match}"
        )
        payment_session.fail! if payment_session.respond_to?(:can_fail?) ? payment_session.can_fail? : true
      end

      payment_session
    rescue Spree::Core::GatewayError
      payment_session.fail! if payment_session.respond_to?(:can_fail?) ? payment_session.can_fail? : true
      payment_session
    end

    # Server-to-server status check. Returns the parsed JSON hash, e.g.
    # { "product_code" => "EPAYTEST", "transaction_uuid" => "...",
    #   "total_amount" => 100.0, "status" => "COMPLETE", "refId" => "..." }.
    def verify_transaction(transaction_uuid:, total_amount:, product_code: nil)
      code = product_code || preferred_product_code
      query = URI.encode_www_form(
        product_code: code,
        total_amount: total_amount,
        transaction_uuid: transaction_uuid
      )
      uri = URI.parse("#{status_check_base_url}?#{query}")

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                                              open_timeout: 10, read_timeout: 15) do |http|
        request = Net::HTTP::Get.new(uri.request_uri)
        request['Accept'] = 'application/json'
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise Spree::Core::GatewayError, "eSewa status check failed (HTTP #{response.code})"
      end

      JSON.parse(response.body)
    rescue JSON::ParserError => e
      raise Spree::Core::GatewayError, "eSewa status check returned invalid JSON: #{e.message}"
    end

    private

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

# frozen_string_literal: true

# Khalti ePayment v2 gateway (redirect + server-side lookup, no webhooks).
#
# Flow (see https://docs.khalti.com/khalti-epayment):
#   1. Storefront creates a PaymentSession. We POST to Khalti's initiate
#      endpoint (amount in paisa) and return `pidx` + `payment_url` in
#      `external_data`; the storefront redirects the customer to `payment_url`.
#   2. Customer pays on Khalti, Khalti redirects back to `return_url?pidx=...`.
#   3. Storefront calls paymentSessions.complete. We POST `pidx` to Khalti's
#      lookup endpoint with `Authorization: Key <secret>` and only complete
#      when `status == "Completed"`.
#
# Credentials live in Spree preferences (admin UI: Settings > Payments),
# never hardcoded. `secret_key` uses the `:password` type so the admin UI
# masks it. Treat DB dumps as containing live secrets.
module Spree
  class PaymentMethod::Khalti < Spree::PaymentMethod
    SANDBOX_BASE_URL = 'https://a.khalti.com/api/v2'
    PRODUCTION_BASE_URL = 'https://khalti.com/api/v2'

    preference :public_key, :string
    preference :secret_key, :password
    preference :env, :string, default: 'sandbox' # sandbox | production

    def payment_icon_name
      'khalti'
    end

    def session_required?
      true
    end

    def source_required?
      false
    end

    def payment_session_class
      Spree::PaymentSessions::Khalti
    end

    def sandbox?
      preferred_env.to_s != 'production'
    end

    def base_url
      sandbox? ? SANDBOX_BASE_URL : PRODUCTION_BASE_URL
    end

    def initiate_url
      "#{base_url}/epayment/initiate/"
    end

    def lookup_url
      "#{base_url}/epayment/lookup/"
    end

    # Amounts: Khalti expects paisa (integer). NPR 100.00 => 10000.
    def amount_in_paisa(amount)
      (BigDecimal(amount.to_s) * 100).to_i
    end

    # Storefront passes redirect targets in `external_data`:
    #   { return_url: "...", website_url: "...", purchase_order_name: "...",
    #     customer_info: { name:, email:, phone: } }
    def create_payment_session(order:, amount: nil, external_data: {})
      total = amount.presence || order.total_minus_store_credits
      paisa = amount_in_paisa(total)
      data = indifferent_params(external_data)

      return_url = data[:return_url] || data[:success_url]
      store_host = order.store.try(:url)
      website_url = data[:website_url] || (store_host.present? ? "https://#{store_host}" : nil)
      purchase_order_id = order.number
      purchase_order_name = data[:purchase_order_name] || "Order #{order.number}"

      payload = {
        'return_url' => return_url.to_s,
        'website_url' => website_url.to_s,
        'amount' => paisa,
        'purchase_order_id' => purchase_order_id,
        'purchase_order_name' => purchase_order_name
      }
      if data[:customer_info].present?
        payload['customer_info'] = data[:customer_info]
      elsif order.email.present?
        bill = order.try(:bill_address)
        full_name = [bill.try(:first_name), bill.try(:last_name)].compact.join(' ').presence || order.email
        payload['customer_info'] = {
          'name' => full_name,
          'email' => order.email,
          'phone' => bill.try(:phone).to_s
        }.reject { |_, v| v.blank? }
      end

      result = initiate_payment(payload)

      pidx = result['pidx']
      raise Spree::Core::GatewayError, 'Khalti initiate did not return a pidx' if pidx.blank?

      # NOTE: create via payment_session_class (not the `payment_sessions`
      # association) so the STI `type` column is populated — the base-class
      # association would insert type=NULL and violate the NOT NULL constraint.
      payment_session_class.create!(
        order: order,
        payment_method: self,
        amount: total,
        currency: order.currency,
        external_id: pidx,
        external_data: {
          'pidx' => pidx,
          'payment_url' => result['payment_url'],
          'expires_at' => result['expires_at'],
          'expires_in' => result['expires_in'],
          'purchase_order_id' => purchase_order_id,
          'purchase_order_name' => purchase_order_name,
          'amount_paisa' => paisa,
          'return_url' => return_url.to_s
        }.compact,
        customer: order.try(:customer) || order.try(:user)
      )
    end

    # pidx is amount-bound at Khalti — if the total changed the storefront
    # should create a new session; we still persist the new amount locally.
    def update_payment_session(payment_session:, amount: nil, external_data: {})
      attrs = {}
      attrs[:amount] = amount if amount.present?

      if external_data.present?
        attrs[:external_data] = (payment_session.external_data || {}).merge(indifferent_params(external_data))
      end

      payment_session.update!(attrs) if attrs.any?
      payment_session
    end

    # Verify server-to-server via the lookup endpoint. The client-supplied
    # pidx (if any) must match our session's pidx — otherwise fail.
    def complete_payment_session(payment_session:, params: {})
      params = indifferent_params(params)
      supplied_pidx = params[:pidx] || params.dig(:external_data, :pidx) || params.dig('external_data', 'pidx')

      if supplied_pidx.present? && supplied_pidx.to_s != payment_session.external_id.to_s
        Rails.logger.warn(
          "[Khalti] pidx mismatch for session #{payment_session.id}: " \
          "expected=#{payment_session.external_id.inspect} got=#{supplied_pidx.inspect}"
        )
        payment_session.fail! if payment_session.respond_to?(:can_fail?) ? payment_session.can_fail? : true
        return payment_session
      end

      result = lookup_payment(payment_session.external_id)
      status = result['status'].to_s
      expected_paisa = amount_in_paisa(payment_session.amount)
      returned_paisa = result['total_amount'] ? result['total_amount'].to_i : nil
      amounts_match = returned_paisa.nil? || returned_paisa == expected_paisa

      if status == 'Completed' && amounts_match
        payment_session.process! if payment_session.respond_to?(:can_process?) ? payment_session.can_process? : true

        payment = payment_session.find_or_create_payment!

        if payment.present? && !payment.completed?
          payment.started_processing! if payment.checkout?
          payment.complete! if payment.can_complete?
        end

        payment_session.complete! unless payment_session.completed?
      else
        Rails.logger.warn(
          "[Khalti] lookup failed for #{payment_session.external_id}: " \
          "status=#{status.inspect} amounts_match=#{amounts_match}"
        )
        payment_session.fail! if payment_session.respond_to?(:can_fail?) ? payment_session.can_fail? : true
      end

      payment_session
    rescue Spree::Core::GatewayError
      payment_session.fail! if payment_session.respond_to?(:can_fail?) ? payment_session.can_fail? : true
      payment_session
    end

    # POST {initiate_url} with `Authorization: Key <secret>`.
    # Returns parsed JSON: { "pidx" => ..., "payment_url" => ..., ... }.
    def initiate_payment(payload)
      post_json(initiate_url, payload)
    end

    # POST {lookup_url} { pidx: } with `Authorization: Key <secret>`.
    # Returns parsed JSON: { "pidx" => ..., "status" => "Completed"|...,
    #   "total_amount" => <paisa>, "transaction_id" => ... }.
    def lookup_payment(pidx)
      post_json(lookup_url, { 'pidx' => pidx })
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

    def post_json(url, payload)
      uri = URI.parse(url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                                              open_timeout: 10, read_timeout: 15) do |http|
        request = Net::HTTP::Post.new(uri.request_uri)
        request['Content-Type'] = 'application/json'
        request['Accept'] = 'application/json'
        request['Authorization'] = "Key #{preferred_secret_key}"
        request.body = payload.to_json
        http.request(request)
      end

      begin
        body = JSON.parse(response.body.to_s)
      rescue JSON::ParserError => e
        raise Spree::Core::GatewayError, "Khalti returned invalid JSON: #{e.message}"
      end

      unless response.is_a?(Net::HTTPSuccess)
        message = body['detail'] || body['error'] || response.body.to_s.truncate(300)
        raise Spree::Core::GatewayError, "Khalti request failed (HTTP #{response.code}): #{message}"
      end

      body
    end
  end
end

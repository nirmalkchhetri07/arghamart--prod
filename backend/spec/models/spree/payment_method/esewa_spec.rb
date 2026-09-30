# frozen_string_literal: true

require 'rails_helper'
require 'webmock/rspec'

# Covers the eSewa redirect+verify flow (no webhooks):
#  - successful PaymentSession creation (form fields + signature)
#  - HMAC-SHA256 correctness (verified vector — see note below)
#  - completed verification path (status == COMPLETE via status-check API)
#  - failed / tampered verification path (never trust client `data` alone)
#
# Outbound HTTP to the eSewa sandbox is stubbed with WebMock (inline stubs,
# no VCR cassettes — deterministic, no live calls, no secrets in the repo).
# Fixtures use the public UAT credentials from the eSewa docs
# (product_code EPAYTEST, secret 8gBm/:&EnhH.1/q) — safe to commit,
# sandbox-only. Nothing beyond sandbox is wired in.
RSpec.describe Spree::PaymentMethod::Esewa, type: :model do
  let(:store) { @default_store || create(:store) }
  let(:order) { create(:order_with_line_items, store: store) }

  let(:payment_method) do
    described_class.create!(
      name: 'eSewa',
      active: true,
      store: store,
      preferred_product_code: 'EPAYTEST',
      preferred_secret_key: '8gBm/:&EnhH.1/q',
      preferred_env: 'sandbox'
    )
  end

  # NOTE: no \A anchor — WebMock matches against the full URI string
  # ("https://rc.esewa…"), so an anchored pattern never matches.
  let(:status_url_pattern) { %r{rc\.esewa\.com\.np/api/epay/transaction/status/} }

  # eSewa redirect-payload fixtures (see #validate_esewa_response): the
  # fields listed in signed_field_names (including that list itself) are
  # signed in order, and total_amount is embedded as a raw JSON number —
  # no quotes — so the validator's canonicalization is exercised rather
  # than bypassed.
  #
  # `signed_amount` is what the HMAC covers; `json_amount` is what the
  # payload carries. They only differ for the tampering case.
  let(:signed_field_names) do
    'transaction_code,status,total_amount,transaction_uuid,product_code,signed_field_names'
  end
  let(:secret_key) { '8gBm/:&EnhH.1/q' }

  def redirect_data(signed_amount: '110.0', json_amount: signed_amount, secret: secret_key)
    signed = [
      ['transaction_code', '000AWEO'],
      ['status', 'COMPLETE'],
      ['total_amount', signed_amount],
      ['transaction_uuid', '240610-162413-1234'],
      ['product_code', 'EPAYTEST'],
      ['signed_field_names', signed_field_names]
    ]
    raw = OpenSSL::HMAC.digest(
      'sha256', secret, signed.map { |k, v| "#{k}=#{v}" }.join(',')
    )
    signature = Base64.strict_encode64(raw)

    json = '{"transaction_code":"000AWEO","status":"COMPLETE",' \
           "\"total_amount\":#{json_amount}," \
           '"transaction_uuid":"240610-162413-1234","product_code":"EPAYTEST",' \
           "\"signed_field_names\":\"#{signed_field_names}\"," \
           "\"signature\":\"#{signature}\"}"
    Base64.strict_encode64(json)
  end

  describe 'payment session interface' do
    it 'uses the Payment Session pattern' do
      expect(payment_method.session_required?).to be(true)
      expect(payment_method.source_required?).to be(false)
      expect(payment_method.payment_session_class).to eq(Spree::PaymentSessions::Esewa)
    end

    it 'is registered in Spree.payment_methods' do
      expect(Spree.payment_methods).to include(described_class)
    end
  end

  describe '#create_payment_session' do
    it 'builds signed eSewa form fields (no outbound call)' do
      session = payment_method.create_payment_session(
        order: order,
        external_data: {
          success_url: 'https://example.com/checkout/esewa/success',
          failure_url: 'https://example.com/checkout/esewa/failure'
        }
      )

      expect(session).to be_persisted
      expect(session.type).to eq('Spree::PaymentSessions::Esewa')
      expect(session.external_id).to be_present
      expect(session.amount).to eq(order.total_minus_store_credits)

      fields = session.external_data['form_fields']
      expect(session.external_data['form_url']).to eq('https://rc-epay.esewa.com.np/api/epay/main/v2/form')
      expect(session.redirect_url).to eq('https://rc-epay.esewa.com.np/api/epay/main/v2/form')
      expect(fields['product_code']).to eq('EPAYTEST')
      expect(fields['transaction_uuid']).to eq(session.external_id)
      expect(fields['total_amount']).to be_present
      expect(fields['signed_field_names']).to eq('total_amount,transaction_uuid,product_code')
      expect(fields['signature']).to be_present
      expect(fields['success_url']).to eq('https://example.com/checkout/esewa/success')
      expect(fields['failure_url']).to eq('https://example.com/checkout/esewa/failure')
    end
  end

  describe '#generate_signature' do
    it 'computes the verified HMAC-SHA256 vector' do
      # NOTE on the "official" vector: eSewa's doc page quotes
      # 4Ov7pCI1zIOdwtV2BRMUNjz1upIlT/COTxfLhWvVurE= for the message
      # "total_amount=100,transaction_uuid=11-201-13,product_code=EPAYTEST"
      # with secret "8gBm/:&EnhH.1/q", but that value does NOT verify —
      # two independent HMAC-SHA256 implementations (Ruby OpenSSL here
      # and Python hashlib) both produce the value asserted below, and no
      # reasonable message variant reproduces the quoted value. The doc
      # value is erroneous (copy-pasted across tutorials); the
      # construction here follows the documented algorithm exactly.
      signature = payment_method.generate_signature(
        total_amount: '100',
        transaction_uuid: '11-201-13',
        product_code: 'EPAYTEST'
      )
      expect(signature).to eq('5DZywcrTKD0gia/rsSMcrRHmJl+4Tbol6S+lWgdJ94E=')
    end

    it 'is verifiable by recomputing over the session fields' do
      session = payment_method.create_payment_session(order: order, external_data: { return_url: 'https://example.com/cb' })
      fields = session.external_data['form_fields']
      recomputed = payment_method.generate_signature(
        total_amount: fields['total_amount'],
        transaction_uuid: fields['transaction_uuid'],
        product_code: fields['product_code']
      )
      expect(fields['signature']).to eq(recomputed)
    end
  end

  describe '#validate_esewa_response' do
    it 'accepts a payload signed with the gateway secret' do
      expect(payment_method.validate_esewa_response(redirect_data)).to be(true)
    end

    it 'rejects an amount tampered after signing' do
      payload = redirect_data(json_amount: '1.0') # attacker swaps 110.0 for 1.0
      expect(payment_method.validate_esewa_response(payload)).to be(false)
    end

    it 'rejects a payload signed with the wrong secret' do
      payload = redirect_data(secret: 'wrong-secret')
      expect(payment_method.validate_esewa_response(payload)).to be(false)
      # …and the same payload verifies when its own secret is supplied.
      expect(payment_method.validate_esewa_response(payload, 'wrong-secret')).to be(true)
    end

    it 'rejects garbage without raising' do
      expect(payment_method.validate_esewa_response('!!!not-base64!!!')).to be(false)
      expect(payment_method.validate_esewa_response(Base64.strict_encode64('just a string'))).to be(false)
      expect(payment_method.validate_esewa_response(Base64.strict_encode64('{"status":"COMPLETE"}'))).to be(false)
      expect(payment_method.validate_esewa_response(nil)).to be(false)
      expect(payment_method.validate_esewa_response('')).to be(false)
    end

    it 'accepts an unpadded Base64 payload' do
      expect(payment_method.validate_esewa_response(redirect_data.delete('='))).to be(true)
    end
  end

  describe '#complete_payment_session' do
    let!(:session) do
      payment_method.create_payment_session(order: order, external_data: { return_url: 'https://example.com/cb' })
    end

    def stub_payment_creation(payment_session)
      payment = instance_double(
        Spree::Payment,
        completed?: false,
        checkout?: true,
        can_complete?: true
      )
      allow(payment).to receive(:started_processing!)
      allow(payment).to receive(:complete!)
      allow(payment_session).to receive(:find_or_create_payment!).and_return(payment)
      payment
    end

    def stub_status_check(body)
      stub_request(:get, status_url_pattern)
        .with(query: hash_including(
          'product_code' => 'EPAYTEST',
          'transaction_uuid' => session.external_id
        ))
        .to_return(status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    it 'completes when the status-check endpoint returns COMPLETE' do
      stub_payment_creation(session)
      stub_status_check(
        'product_code' => 'EPAYTEST',
        'transaction_uuid' => session.external_id,
        'total_amount' => session.amount.to_f,
        'status' => 'COMPLETE',
        'refId' => '000AWEO'
      )

      # A forged client `data` param must not influence the verdict — the
      # stubbed server-side status check above is authoritative.
      payment_method.complete_payment_session(payment_session: session, params: { data: 'forged' })

      expect(session.reload.status).to eq('completed')
      expect(a_request(:get, status_url_pattern)).to have_been_made.once
    end

    it 'fails when eSewa reports a non-COMPLETE status' do
      stub_status_check('status' => 'PENDING')

      expect(session).not_to receive(:find_or_create_payment!)
      payment_method.complete_payment_session(payment_session: session, params: {})

      expect(session.reload.status).to eq('failed')
    end

    it 'fails on tampered amounts even when status is COMPLETE' do
      stub_status_check(
        'status' => 'COMPLETE',
        'total_amount' => (session.amount.to_f + 1000.0) # attacker inflated the provider-side total
      )

      expect(session).not_to receive(:find_or_create_payment!)
      payment_method.complete_payment_session(payment_session: session, params: {})

      expect(session.reload.status).to eq('failed')
    end

    it 'logs a verified redirect payload' do
      allow(Rails.logger).to receive(:info).and_call_original
      allow(Rails.logger).to receive(:warn).and_call_original
      expect(Rails.logger).to receive(:info).with(/signature valid: true/)

      stub_payment_creation(session)
      stub_status_check('status' => 'COMPLETE', 'total_amount' => session.amount.to_f)

      payment_method.complete_payment_session(
        payment_session: session,
        params: { data: redirect_data }
      )

      expect(session.reload.status).to eq('completed')
    end

    it 'warns on a bad redirect signature but still defers to the status check' do
      allow(Rails.logger).to receive(:info).and_call_original
      allow(Rails.logger).to receive(:warn).and_call_original
      expect(Rails.logger).to receive(:warn).with(/signature did not verify/)

      stub_payment_creation(session)
      stub_status_check('status' => 'COMPLETE', 'total_amount' => session.amount.to_f)

      # Signed over 110.0 but carries 1.0 — forged, yet the server-to-server
      # status check (which never sees this payload) stays authoritative.
      payment_method.complete_payment_session(
        payment_session: session,
        params: { data: redirect_data(json_amount: '1.0') }
      )

      expect(session.reload.status).to eq('completed')
    end
  end
end

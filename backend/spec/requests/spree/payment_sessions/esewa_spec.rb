# frozen_string_literal: true

require 'rails_helper'
require 'spree/api/testing_support/v3/base'
require 'webmock/rspec'

# End-to-end coverage of the eSewa redirect+verify flow through the Store API
# (no webhooks):
#  - POST …/payment_sessions creates a session with signed eSewa form fields
#    (HMAC correctness asserted by recomputation + the fixed vector in the
#    model spec)
#  - PATCH …/complete with a COMPLETE status-check stub completes the session
#    and creates the Spree::Payment — even with a forged client `data` param
#  - PATCH …/complete with a non-COMPLETE stub fails the session and creates
#    no payment
#
# Outbound HTTP to the eSewa sandbox is stubbed with WebMock (inline stubs,
# no VCR cassettes — deterministic, no live calls). Fixtures use the public
# UAT credentials (EPAYTEST / 8gBm/:&EnhH.1/q), sandbox-only.
#
# Assumptions (per the documented 'API v3 Store' shared context + Store API
# reference — confirm on the first run, no Ruby runtime was available here):
#  - the context provides `store` (default store) and `api_key` (publishable key)
#  - guest carts authorize via the `X-Spree-Token: order.token` header
#  - cart / payment-method / session ids accept prefixed ids in paths
RSpec.describe 'Store API payment sessions (eSewa)', type: :request do
  include_context 'API v3 Store'

  let(:order) { create(:order_with_line_items, store: store) }
  let(:payment_method) do
    Spree::PaymentMethod::Esewa.create!(
      name: 'eSewa',
      active: true,
      display_on: 'front_end',
      store: store,
      preferred_product_code: 'EPAYTEST',
      preferred_secret_key: '8gBm/:&EnhH.1/q',
      preferred_env: 'sandbox'
    )
  end

  let(:headers) do
    {
      'X-Spree-Api-Key' => api_key.token,
      'X-Spree-Token' => order.token,
      'Content-Type' => 'application/json'
    }
  end

  # NOTE: no \A anchor — WebMock matches against the full URI string
  # ("https://rc.esewa…"), so an anchored pattern never matches.
  let(:status_url_pattern) { %r{rc\.esewa\.com\.np/api/epay/transaction/status/} }

  def stub_status_check(body)
    stub_request(:get, status_url_pattern)
      .to_return(status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe 'POST /api/v3/store/carts/:cart_id/payment_sessions' do
    it 'creates a session with signed form fields' do
      post "/api/v3/store/carts/#{order.prefixed_id}/payment_sessions",
           params: {
             payment_method_id: payment_method.prefixed_id,
             external_data: {
               success_url: 'https://example.com/checkout/esewa/success',
               failure_url: 'https://example.com/checkout/esewa/failure'
             }
           }.to_json,
           headers: headers

      expect(response).to have_http_status(:created)

      fields = json_response['external_data']['form_fields']
      expect(json_response['status']).to eq('pending')
      expect(json_response['external_id']).to be_present
      expect(json_response['external_data']['form_url'])
        .to eq('https://rc-epay.esewa.com.np/api/epay/main/v2/form')
      expect(fields['product_code']).to eq('EPAYTEST')
      expect(fields['transaction_uuid']).to eq(json_response['external_id'])
      expect(fields['signed_field_names']).to eq('total_amount,transaction_uuid,product_code')

      # HMAC correctness: recompute over the returned fields.
      message = "total_amount=#{fields['total_amount']}," \
                "transaction_uuid=#{fields['transaction_uuid']}," \
                "product_code=#{fields['product_code']}"
      expected = Base64.strict_encode64(
        OpenSSL::HMAC.digest('sha256', '8gBm/:&EnhH.1/q', message)
      )
      expect(fields['signature']).to eq(expected)
    end
  end

  describe 'PATCH /api/v3/store/carts/:cart_id/payment_sessions/:id/complete' do
    let!(:session) do
      payment_method.create_payment_session(
        order: order,
        external_data: { return_url: 'https://example.com/cb' }
      )
    end

    it 'completes on COMPLETE and creates the payment (ignores forged client data)' do
      stub_status_check(
        'product_code' => 'EPAYTEST',
        'transaction_uuid' => session.external_id,
        'total_amount' => session.amount.to_f,
        'status' => 'COMPLETE',
        'refId' => '000AWEO'
      )

      patch "/api/v3/store/carts/#{order.prefixed_id}/payment_sessions/#{session.prefixed_id}/complete",
            params: { external_data: { data: 'forged-client-payload' } }.to_json,
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response['status']).to eq('completed')
      expect(Spree::Payment.where(response_code: session.external_id)).to exist
      expect(a_request(:get, status_url_pattern)).to have_been_made.once
    end

    it 'fails on non-COMPLETE and creates no payment' do
      stub_status_check('status' => 'PENDING')

      patch "/api/v3/store/carts/#{order.prefixed_id}/payment_sessions/#{session.prefixed_id}/complete",
            params: {}.to_json,
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response['status']).to eq('failed')
      expect(Spree::Payment.where(response_code: session.external_id)).not_to exist
    end
  end
end

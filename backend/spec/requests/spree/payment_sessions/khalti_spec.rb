# frozen_string_literal: true

require 'rails_helper'
require 'spree/api/testing_support/v3/base'
require 'webmock/rspec'

# End-to-end coverage of the Khalti redirect+verify flow through the Store API
# (no webhooks):
#  - POST …/payment_sessions initiates with Khalti (paisa amount) and stores
#    pidx + payment_url
#  - PATCH …/complete with a Completed lookup completes the session and
#    creates the Spree::Payment
#  - PATCH …/complete with a non-Completed lookup fails the session and
#    creates no payment
#
# Outbound HTTP to the Khalti sandbox is stubbed with WebMock (inline stubs,
# no VCR cassettes — deterministic, no live calls). Specs use placeholder
# keys; real sandbox keys from a.khalti.com are for manual testing only and
# must never be committed. Nothing beyond sandbox is wired in.
#
# Assumptions (per the documented 'API v3 Store' shared context + Store API
# reference — confirm on the first run, no Ruby runtime was available here):
#  - the context provides `store` (default store) and `api_key` (publishable key)
#  - guest carts authorize via the `X-Spree-Token: order.token` header
#  - cart / payment-method / session ids accept prefixed ids in paths
RSpec.describe 'Store API payment sessions (Khalti)', type: :request do
  include_context 'API v3 Store'

  let(:order) { create(:order_with_line_items, store: store) }
  let(:payment_method) do
    Spree::PaymentMethod::Khalti.create!(
      name: 'Khalti',
      active: true,
      display_on: 'front_end',
      store: store,
      preferred_public_key: 'test_public_key',
      preferred_secret_key: 'test_secret_key',
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

  let(:initiate_url) { 'https://a.khalti.com/api/v2/epayment/initiate/' }
  let(:lookup_url) { 'https://a.khalti.com/api/v2/epayment/lookup/' }
  let(:auth_header) { { 'Authorization' => 'Key test_secret_key' } }

  describe 'POST /api/v3/store/carts/:cart_id/payment_sessions' do
    before do
      stub_request(:post, initiate_url)
        .with(headers: auth_header)
        .to_return(status: 200,
                   body: {
                     'pidx' => 'bZQLD9wRVWo4CdESSfuSsB',
                     'payment_url' => 'https://test-pay.khalti.com/?pidx=bZQLD9wRVWo4CdESSfuSsB',
                     'expires_at' => '2026-01-01T12:00:00+05:45',
                     'expires_in' => 1800
                   }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'initiates with Khalti and stores pidx + payment_url' do
      post "/api/v3/store/carts/#{order.prefixed_id}/payment_sessions",
           params: {
             payment_method_id: payment_method.prefixed_id,
             external_data: {
               return_url: 'https://example.com/checkout/khalti/return',
               website_url: 'https://example.com'
             }
           }.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
      expect(json_response['status']).to eq('pending')
      expect(json_response['external_id']).to eq('bZQLD9wRVWo4CdESSfuSsB')
      expect(json_response['external_data']['pidx']).to eq('bZQLD9wRVWo4CdESSfuSsB')
      expect(json_response['external_data']['payment_url']).to include('test-pay.khalti.com')

      # Amount must go out in paisa with the secret-key auth header.
      expect(a_request(:post, initiate_url)
        .with(headers: auth_header,
              body: hash_including(
                'amount' => (BigDecimal(order.total_minus_store_credits.to_s) * 100).to_i,
                'purchase_order_id' => order.number
              ))).to have_been_made.once
    end
  end

  describe 'PATCH /api/v3/store/carts/:cart_id/payment_sessions/:id/complete' do
    let!(:session) do
      stub_request(:post, initiate_url)
        .to_return(status: 200,
                   body: {
                     'pidx' => 'test-pidx-123',
                     'payment_url' => 'https://test-pay.khalti.com/?pidx=test-pidx-123',
                     'expires_at' => nil,
                     'expires_in' => 1800
                   }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      payment_method.create_payment_session(
        order: order,
        external_data: { return_url: 'https://example.com/checkout/khalti/return', website_url: 'https://example.com' }
      )
    end

    def stub_lookup(body)
      stub_request(:post, lookup_url)
        .with(headers: auth_header)
        .to_return(status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    it 'completes on Completed and creates the payment' do
      stub_lookup(
        'pidx' => 'test-pidx-123',
        'status' => 'Completed',
        'total_amount' => (BigDecimal(session.amount.to_s) * 100).to_i,
        'transaction_id' => 'GFq9PFS7b2iYvL8LrR3xYZ'
      )

      patch "/api/v3/store/carts/#{order.prefixed_id}/payment_sessions/#{session.prefixed_id}/complete",
            params: { external_data: { pidx: 'test-pidx-123' } }.to_json,
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response['status']).to eq('completed')
      expect(Spree::Payment.where(response_code: 'test-pidx-123')).to exist
    end

    it 'fails on non-Completed and creates no payment' do
      stub_lookup(
        'pidx' => 'test-pidx-123',
        'status' => 'Expired',
        'total_amount' => (BigDecimal(session.amount.to_s) * 100).to_i
      )

      patch "/api/v3/store/carts/#{order.prefixed_id}/payment_sessions/#{session.prefixed_id}/complete",
            params: { external_data: { pidx: 'test-pidx-123' } }.to_json,
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response['status']).to eq('failed')
      expect(Spree::Payment.where(response_code: 'test-pidx-123')).not_to exist
    end
  end
end

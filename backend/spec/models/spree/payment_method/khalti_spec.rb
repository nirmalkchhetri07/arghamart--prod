# frozen_string_literal: true

require 'rails_helper'
require 'webmock/rspec'

# Covers the Khalti redirect+verify flow (no webhooks):
#  - successful PaymentSession creation via the initiate endpoint
#    (amount in paisa, pidx + payment_url stored in external_data)
#  - completed verification path (lookup status == Completed)
#  - failed / tampered verification path (pidx mismatch, non-Completed status,
#    amount mismatch)
#
# Outbound HTTP to the Khalti sandbox is stubbed with WebMock (inline stubs,
# no VCR cassettes — deterministic, no live calls, no secrets in the repo).
# Specs use placeholder keys — plug in real sandbox keys from a.khalti.com
# only for manual testing, never commit them. Nothing beyond sandbox is
# wired in.
RSpec.describe Spree::PaymentMethod::Khalti, type: :model do
  let(:store) { @default_store || create(:store) }
  let(:order) { create(:order_with_line_items, store: store) }

  let(:payment_method) do
    described_class.create!(
      name: 'Khalti',
      active: true,
      store: store,
      preferred_public_key: 'test_public_key',
      preferred_secret_key: 'test_secret_key',
      preferred_env: 'sandbox'
    )
  end

  let(:initiate_url) { 'https://a.khalti.com/api/v2/epayment/initiate/' }
  let(:lookup_url) { 'https://a.khalti.com/api/v2/epayment/lookup/' }
  let(:auth_header) { { 'Authorization' => 'Key test_secret_key' } }

  describe 'payment session interface' do
    it 'uses the Payment Session pattern' do
      expect(payment_method.session_required?).to be(true)
      expect(payment_method.source_required?).to be(false)
      expect(payment_method.payment_session_class).to eq(Spree::PaymentSessions::Khalti)
    end

    it 'is registered in Spree.payment_methods' do
      expect(Spree.payment_methods).to include(described_class)
    end

    it 'sends amounts in paisa' do
      expect(payment_method.amount_in_paisa('100')).to eq(10_000)
      expect(payment_method.amount_in_paisa(BigDecimal('99.99'))).to eq(9999)
    end
  end

  describe '#create_payment_session' do
    let(:initiate_response) do
      {
        'pidx' => 'bZQLD9wRVWo4CdESSfuSsB',
        'payment_url' => 'https://test-pay.khalti.com/?pidx=bZQLD9wRVWo4CdESSfuSsB',
        'expires_at' => '2026-01-01T12:00:00+05:45',
        'expires_in' => 1800
      }
    end

    before do
      stub_request(:post, initiate_url)
        .with(headers: auth_header)
        .to_return(status: 200, body: initiate_response.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    it 'initiates with Khalti and stores pidx + payment_url' do
      session = payment_method.create_payment_session(
        order: order,
        external_data: {
          return_url: 'https://example.com/checkout/khalti/return',
          website_url: 'https://example.com'
        }
      )

      expect(session).to be_persisted
      expect(session.type).to eq('Spree::PaymentSessions::Khalti')
      expect(session.external_id).to eq('bZQLD9wRVWo4CdESSfuSsB')
      expect(session.external_data['pidx']).to eq('bZQLD9wRVWo4CdESSfuSsB')
      expect(session.external_data['payment_url']).to include('test-pay.khalti.com')
      expect(session.payment_url).to include('test-pay.khalti.com')
      expect(session.amount).to eq(order.total_minus_store_credits)

      # Amount must go out in paisa with the secret-key auth header.
      expect(a_request(:post, initiate_url)
        .with(headers: auth_header,
              body: hash_including(
                'amount' => payment_method.amount_in_paisa(order.total_minus_store_credits),
                'purchase_order_id' => order.number,
                'return_url' => 'https://example.com/checkout/khalti/return'
              ))).to have_been_made.once
    end
  end

  describe '#complete_payment_session' do
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

    def stub_lookup(body)
      stub_request(:post, lookup_url)
        .with(headers: auth_header)
        .to_return(status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    it 'completes when lookup returns Completed with a matching amount' do
      stub_payment_creation(session)
      stub_lookup(
        'pidx' => 'test-pidx-123',
        'status' => 'Completed',
        'total_amount' => payment_method.amount_in_paisa(session.amount),
        'transaction_id' => 'GFq9PFS7b2iYvL8LrR3xYZ'
      )

      payment_method.complete_payment_session(payment_session: session, params: { pidx: 'test-pidx-123' })

      expect(session.reload.status).to eq('completed')
      expect(a_request(:post, lookup_url)
        .with(headers: auth_header, body: { pidx: 'test-pidx-123' }.to_json)).to have_been_made.once
    end

    it 'fails when lookup reports a non-Completed status' do
      stub_lookup(
        'pidx' => 'test-pidx-123',
        'status' => 'Expired',
        'total_amount' => payment_method.amount_in_paisa(session.amount)
      )

      expect(session).not_to receive(:find_or_create_payment!)
      payment_method.complete_payment_session(payment_session: session, params: { pidx: 'test-pidx-123' })

      expect(session.reload.status).to eq('failed')
    end

    it 'fails when the client-supplied pidx does not match the session' do
      expect(session).not_to receive(:find_or_create_payment!)

      payment_method.complete_payment_session(payment_session: session, params: { pidx: 'attacker-pidx' })

      expect(session.reload.status).to eq('failed')
      expect(a_request(:post, lookup_url)).not_to have_been_made
    end

    it 'fails on tampered amounts even when status is Completed' do
      stub_lookup(
        'pidx' => 'test-pidx-123',
        'status' => 'Completed',
        'total_amount' => payment_method.amount_in_paisa(session.amount) + 100_000
      )

      expect(session).not_to receive(:find_or_create_payment!)
      payment_method.complete_payment_session(payment_session: session, params: { pidx: 'test-pidx-123' })

      expect(session.reload.status).to eq('failed')
    end
  end
end

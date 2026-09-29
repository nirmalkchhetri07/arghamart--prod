# frozen_string_literal: true

require 'rails_helper'
require 'spree/api/testing_support/v3/base'
require 'webmock/rspec'

# End-to-end coverage of the Manual QR proof flow through the Store API:
#   session create → proof upload → session complete (payment stays pending)
#   → re-upload after rejection → owner-only proof viewing.
#
# Assumptions (per the documented 'API v3 Store' shared context + the eSewa
# request spec — same conventions):
#   - the context provides `store` (default store) and `api_key` (publishable key)
#   - guest carts authorize via the `X-Spree-Token: order.token` header
#   - cart / payment-method / session ids accept prefixed ids in paths
RSpec.describe 'Store API Manual QR proofs', type: :request do
  include_context 'API v3 Store'

  # Manual QR is NPR-only: teach the test store NPR (markets + legacy column).
  let!(:store_override) do
    store.markets.update_all(currency: 'NPR') if store.respond_to?(:markets)
    store.update!(supported_currencies: 'USD,NPR') if store.has_attribute?(:supported_currencies)
    store.reload
  end

  let(:order) do
    create(:order_with_line_items, store: store, currency: 'NPR')
  end
  let(:payment_method) do
    Spree::PaymentMethod::ManualQr.create!(
      name: 'Manual QR',
      active: true,
      display_on: 'front_end',
      store: store,
      preferred_instructions: 'Pay to ArghaMart.'
    )
  end

  let(:headers) do
    {
      'X-Spree-Api-Key' => api_key.token,
      'X-Spree-Token' => order.token,
      'Content-Type' => 'application/json'
    }
  end
  let(:multipart_headers) do
    {
      'X-Spree-Api-Key' => api_key.token,
      'X-Spree-Token' => order.token
    }
  end

  def proof_file
    fixture_file_upload(
      Rails.root.join('spec/fixtures/files/qr-proof.png'), 'image/png'
    )
  end

  def create_qr_session
    post "/api/v3/store/carts/#{order.prefixed_id}/payment_sessions",
         params: { payment_method_id: payment_method.prefixed_id }.to_json,
         headers: headers
    expect(response).to have_http_status(:created)
    json_response
  end

  def upload_qr_proof(session_id, file = proof_file, req_headers = multipart_headers)
    post "/api/v3/store/carts/#{order.prefixed_id}/payment_sessions/#{session_id}/proof",
         params: { proof_image: file },
         headers: req_headers
  end

  def complete_qr_session(session_id, transaction_id = 'TXN123')
    patch "/api/v3/store/carts/#{order.prefixed_id}/payment_sessions/#{session_id}/complete",
          params: { external_data: { transaction_id: transaction_id } }.to_json,
          headers: headers
  end

  describe 'POST payment_sessions (Manual QR)' do
    it 'returns the QR payload for the storefront' do
      body = create_qr_session

      expect(body['status']).to eq('pending')
      expect(body['external_data']['instructions']).to eq('Pay to ArghaMart.')
      expect(body['external_data']['currency']).to eq('NPR')
      expect(body['external_data']['amount']).to be_present
    end
  end

  describe 'POST proof upload' do
    it 'attaches a valid screenshot to the session' do
      session = create_qr_session

      upload_qr_proof(session['id'])

      expect(response).to have_http_status(:created)
      stored = Spree::PaymentSessions::ManualQr.find_by!(external_id: session['external_id'])
      expect(stored.proof_image).to be_attached
    end

    it 'completes the flow: upload → complete leaves payment pending with proof' do
      session = create_qr_session
      upload_qr_proof(session['id'])
      complete_qr_session(session['id'])

      expect(response).to have_http_status(:ok)
      expect(json_response['status']).to eq('completed')
      payment = Spree::Payment.find_by!(response_code: session['external_id'])
      expect(payment).to be_pending
      expect(payment.proof_image).to be_attached
      expect(payment.qr_transaction_id).to eq('TXN123')
      expect(payment.qr_status).to eq('pending')
    end

    it 'fails completion when no proof was uploaded' do
      session = create_qr_session
      complete_qr_session(session['id'])

      expect(json_response['status']).to eq('failed')
      expect(Spree::Payment.where(response_code: session['external_id'])).not_to exist
    end

    it 'rejects non-image uploads with 422' do
      session = create_qr_session
      upload_qr_proof(session['id'],
                   fixture_file_upload(Rails.root.join('spec/fixtures/files/not-an-image.txt'), 'text/plain'))

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'rejects screenshots over 5 MB with 422' do
      # 5.5 MB: passes the API body cap (6 MB, see spree.rb) so the request
      # reaches the proof validation, which caps screenshots at 5 MB.
      raw = File.binread(Rails.root.join('spec/fixtures/files/qr-proof.png'))
      big = Tempfile.new(['big-proof', '.png'])
      big.binmode
      big.write(raw)
      big.write('0' * (5 * 1024 * 1024 + 512 * 1024))
      big.rewind

      session = create_qr_session
      post "/api/v3/store/carts/#{order.prefixed_id}/payment_sessions/#{session['id']}/proof",
           params: { proof_image: Rack::Test::UploadedFile.new(big.path, 'image/png') },
           headers: multipart_headers

      expect(response).to have_http_status(:unprocessable_content)
    ensure
      big.close!
    end

    it 'rejects uploads with a wrong order token (forbidden)' do
      session = create_qr_session
      stranger_headers = multipart_headers.merge('X-Spree-Token' => 'wrong-token')

      upload_qr_proof(session['id'], proof_file, stranger_headers)

      expect(response).to have_http_status(:forbidden)
    end

    it 'rejects uploads to a non-Manual-QR session' do
      esewa = Spree::PaymentMethod::Esewa.create!(
        name: 'eSewa', active: true, display_on: 'front_end', store: store,
        preferred_product_code: 'EPAYTEST', preferred_secret_key: '8gBm/:&EnhH.1/q',
        preferred_env: 'sandbox'
      )
      post "/api/v3/store/carts/#{order.prefixed_id}/payment_sessions",
           params: { payment_method_id: esewa.prefixed_id }.to_json,
           headers: headers
      other = json_response

      upload_qr_proof(other['id'])

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'completed-order re-upload + proof viewing (permissions)' do
    # A completed NPR order whose Manual QR payment was rejected.
    let!(:completed_order) do
      placed = create(:completed_order_with_totals, store: store, currency: 'NPR')
      placed.payments.destroy_all
      payment = placed.payments.create!(
        payment_method: payment_method,
        amount: placed.total,
        response_code: SecureRandom.uuid,
        skip_source_requirement: true
      )
      payment.proof_image.attach(
        io: File.open(Rails.root.join('spec/fixtures/files/qr-proof.png')),
        filename: 'qr-proof.png', content_type: 'image/png'
      )
      payment.pend!
      payment.void!
      placed
    end

    def order_headers(token)
      {
        'X-Spree-Api-Key' => api_key.token,
        'X-Spree-Token' => token,
        'Content-Type' => 'application/json'
      }
    end

    def order_multipart_headers(token)
      { 'X-Spree-Api-Key' => api_key.token, 'X-Spree-Token' => token }
    end

    it 'creates a fresh pending payment on re-upload after rejection' do
      expect do
        post "/api/v3/store/orders/#{completed_order.prefixed_id}/manual_qr_proof",
             params: { proof_image: proof_file, transaction_id: 'TXN999' },
             headers: order_multipart_headers(completed_order.token)
      end.to change { completed_order.payments.count }.by(1)

      expect(response).to have_http_status(:created)
      fresh = completed_order.payments.order(:created_at).last
      expect(fresh).to be_pending
      expect(fresh.proof_image).to be_attached
      expect(fresh.qr_transaction_id).to eq('TXN999')
    end

    it 'refuses re-upload while a payment is still pending review' do
      pending_payment = completed_order.payments.order(:created_at).last
      pending_payment.update!(qr_rejection_reason: nil)
      # void → cannot go back; simulate "under review" with a fresh pending payment
      completed_order.payments.create!(
        payment_method: payment_method, amount: completed_order.total,
        response_code: SecureRandom.uuid, skip_source_requirement: true
      ).pend!

      post "/api/v3/store/orders/#{completed_order.prefixed_id}/manual_qr_proof",
           params: { proof_image: proof_file },
           headers: order_multipart_headers(completed_order.token)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'redirects the owner to the proof image' do
      payment = completed_order.payments.order(:created_at).last

      get "/api/v3/store/orders/#{completed_order.prefixed_id}/payments/#{payment.prefixed_id}/proof",
          headers: order_headers(completed_order.token)

      expect(response).to have_http_status(:redirect)
      expect(response.headers['Location']).to be_present
    end

    it 'hides the proof from strangers (wrong token)' do
      payment = completed_order.payments.order(:created_at).last

      get "/api/v3/store/orders/#{completed_order.prefixed_id}/payments/#{payment.prefixed_id}/proof",
          headers: order_headers('wrong-token')

      expect(response).to have_http_status(:not_found)
    end

    it 'hides the proof without any token' do
      payment = completed_order.payments.order(:created_at).last

      get "/api/v3/store/orders/#{completed_order.prefixed_id}/payments/#{payment.prefixed_id}/proof",
          headers: { 'X-Spree-Api-Key' => api_key.token }

      expect(response).to have_http_status(:not_found)
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

# Manual QR method unit coverage: session payload, proof requirement,
# pending-until-approved flow, upload validations and review status mapping.
RSpec.describe Spree::PaymentMethod::ManualQr, type: :model do
  # Manual QR is NPR-only: teach the test store NPR (markets + legacy column).
  let!(:store) { @default_store || create(:store) }
  before do
    store.markets.update_all(currency: 'NPR') if store.respond_to?(:markets)
    store.update!(supported_currencies: 'USD,NPR') if store.has_attribute?(:supported_currencies)
    store.reload
  end

  let(:order) do
    create(:order_with_line_items, store: store, currency: 'NPR')
  end

  let(:payment_method) do
    described_class.create!(
      name: 'Manual QR',
      active: true,
      display_on: 'front_end',
      store: store,
      preferred_instructions: 'Pay to ArghaMart and upload the screenshot.'
    )
  end

  def attach_qr(record, path = Rails.root.join('spec/fixtures/files/qr-proof.png'))
    record.qr_image.attach(
      io: File.open(path),
      filename: File.basename(path),
      content_type: Marcel::MimeType.for(Pathname.new(path))
    )
    record
  end

  def build_session
    payment_method.create_payment_session(
      order: order, external_data: {}
    )
  end

  def attach_session_proof(session)
    session.proof_image.attach(
      io: File.open(Rails.root.join('spec/fixtures/files/qr-proof.png')),
      filename: 'qr-proof.png',
      content_type: 'image/png'
    )
    session.save!
    session
  end

  describe 'payment method interface' do
    it 'uses the Payment Session pattern without a source' do
      expect(payment_method.session_required?).to be(true)
      expect(payment_method.source_required?).to be(false)
      expect(payment_method.payment_session_class).to eq(Spree::PaymentSessions::ManualQr)
    end

    it 'is registered in Spree.payment_methods' do
      expect(Spree.payment_methods).to include(described_class)
    end

    it 'is only available for NPR orders' do
      expect(payment_method.available_for_order?(order)).to be(true)
      order.update!(currency: 'USD')
      expect(payment_method.available_for_order?(order)).to be(false)
    end
  end

  describe '#create_payment_session' do
    it 'returns the QR image path, instructions and amount' do
      attach_qr(payment_method).save!

      session = build_session

      expect(session).to be_persisted
      expect(session.type).to eq('Spree::PaymentSessions::ManualQr')
      expect(session.external_data['qr_image_url']).to start_with('/rails/active_storage/')
      expect(session.external_data['instructions']).to eq('Pay to ArghaMart and upload the screenshot.')
      expect(session.external_data['currency']).to eq('NPR')
      expect(session.external_data['amount']).to eq(order.total_minus_store_credits.to_s)
    end

    it 'omits the QR url when no QR is configured' do
      session = build_session

      expect(session.external_data['qr_image_url']).to be_nil
      expect(session.external_data['instructions']).to be_present
    end
  end

  describe '#complete_payment_session' do
    it 'fails the session when no proof was uploaded' do
      session = build_session

      payment_method.complete_payment_session(payment_session: session, params: {})

      expect(session.reload.status).to eq('failed')
      expect(Spree::Payment.where(response_code: session.external_id)).not_to exist
    end

    it 'creates a pending payment with the proof and transaction id' do
      session = attach_session_proof(build_session)

      payment_method.complete_payment_session(
        payment_session: session,
        params: { external_data: { transaction_id: 'TXN123' } }
      )

      expect(session.reload.status).to eq('completed')
      payment = Spree::Payment.find_by!(response_code: session.external_id)
      expect(payment).to be_pending
      expect(payment.proof_image).to be_attached
      expect(payment.qr_transaction_id).to eq('TXN123')
      expect(payment.qr_status).to eq('pending')
    end
  end

  describe 'proof validations' do
    it 'rejects non-image uploads' do
      session = build_session
      session.proof_image.attach(
        io: File.open(Rails.root.join('spec/fixtures/files/not-an-image.txt')),
        filename: 'not-an-image.txt',
        content_type: 'text/plain'
      )

      expect(session).not_to be_valid
      expect(session.errors[:proof_image]).to be_present
    end

    it 'rejects screenshots over 5 MB' do
      raw = File.binread(Rails.root.join('spec/fixtures/files/qr-proof.png'))
      big = Tempfile.new(['big-proof', '.png'])
      big.binmode
      big.write(raw)
      big.write('0' * (6 * 1024 * 1024))
      big.rewind

      session = build_session
      session.proof_image.attach(io: big, filename: 'big-proof.png', content_type: 'image/png')

      expect(session).not_to be_valid
      expect(session.errors[:proof_image]).to be_present
    ensure
      big.close!
    end
  end

  describe 'admin review (approve / reject)' do
    it 'completes a pending payment on approve' do
      session = attach_session_proof(build_session)
      payment_method.complete_payment_session(payment_session: session, params: {})
      payment = Spree::Payment.find_by!(response_code: session.external_id)

      payment.complete!

      expect(payment.reload).to be_completed
      expect(payment.qr_status).to eq('verified')
    end

    it 'voids a pending payment on reject and keeps the reason' do
      session = attach_session_proof(build_session)
      payment_method.complete_payment_session(payment_session: session, params: {})
      payment = Spree::Payment.find_by!(response_code: session.external_id)

      payment.update!(qr_rejection_reason: 'Amount does not match.')
      payment.void!

      expect(payment.reload).to be_void
      expect(payment.qr_status).to eq('rejected')
      expect(payment.qr_rejection_reason).to eq('Amount does not match.')
    end
  end
end

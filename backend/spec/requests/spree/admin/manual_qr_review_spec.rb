# frozen_string_literal: true

require 'rails_helper'

# Admin review of Manual QR payments: Approve completes a pending payment,
# Reject voids it with a reason, the proof is served to admins, and the order
# page shows the review UI only for Manual QR payments.
RSpec.describe 'Admin Manual QR review', type: :request do
  # Manual QR is NPR-only: teach the test store NPR (markets + legacy column).
  let!(:store_override) do
    store.markets.update_all(currency: 'NPR') if store.respond_to?(:markets)
    # update_column, not update!: the shared store object may already hold
    # 'USD,NPR' in memory from a rolled-back example, and update! would skip
    # the UPDATE — leaving the DB on USD.
    store.update_column(:supported_currencies, 'USD,NPR') if store.has_attribute?(:supported_currencies)
    store.reload
  end

  let(:store) { @default_store }
  let(:admin_user) { create(:admin_user) }
  let(:qr_method) do
    Spree::PaymentMethod::ManualQr.create!(
      name: 'Manual QR',
      active: true,
      display_on: 'front_end',
      store: store,
      preferred_instructions: 'Pay to ArghaMart.'
    )
  end
  let(:order) do
    create(:completed_order_with_totals, store: store, currency: 'NPR')
  end

  def pending_qr_payment(txn_id: nil, amount: nil)
    order.payments.destroy_all
    payment = order.payments.create!(
      payment_method: qr_method,
      amount: amount || order.reload.total,
      response_code: SecureRandom.uuid,
      skip_source_requirement: true
    )
    payment.proof_image.attach(
      io: File.open(Rails.root.join('spec/fixtures/files/qr-proof.png')),
      filename: 'qr-proof.png', content_type: 'image/png'
    )
    payment.update!(qr_transaction_id: txn_id) if txn_id
    payment.pend!
    payment.reload
  end

  before { login_as(admin_user, scope: :admin_user) }

  it 'approves a pending QR payment (pending → completed, order paid)' do
    payment = pending_qr_payment

    put "/admin/orders/#{order.to_param}/payments/#{payment.to_param}/approve"

    expect(response).to have_http_status(:redirect)
    expect(payment.reload).to be_completed
    expect(payment.qr_status).to eq('verified')
    expect(order.reload.payment_state).to eq('paid')
  end

  it 'rejects a pending QR payment with a reason (pending → void)' do
    payment = pending_qr_payment

    put "/admin/orders/#{order.to_param}/payments/#{payment.to_param}/reject",
        params: { payment: { qr_rejection_reason: 'Amount does not match.' } }

    expect(response).to have_http_status(:redirect)
    expect(payment.reload).to be_void
    expect(payment.qr_status).to eq('rejected')
    expect(payment.qr_rejection_reason).to eq('Amount does not match.')
  end

  it 'refuses to approve an already-completed payment' do
    payment = pending_qr_payment
    payment.complete!

    put "/admin/orders/#{order.to_param}/payments/#{payment.to_param}/approve"

    expect(response).to have_http_status(:redirect)
    expect(payment.reload).to be_completed
    expect(flash[:error]).to be_present
  end

  # A failure inside the state transition (storage, validation, webhook, …)
  # must land in the flash with its reason — otherwise the admin is bounced
  # back to the order page with no explanation (or a bare 500).
  it 'shows why Approve failed instead of failing silently' do
    payment = pending_qr_payment
    allow_any_instance_of(Spree::Payment).to receive(:complete!)
      .and_raise(RuntimeError, 'R2 unreachable while completing the payment')

    put "/admin/orders/#{order.to_param}/payments/#{payment.to_param}/approve"

    expect(response).to have_http_status(:redirect)
    expect(payment.reload).to be_pending
    expect(flash[:error]).to include('Could not approve this payment')
    expect(flash[:error]).to include('R2 unreachable while completing the payment')
  end

  it 'shows why Reject failed instead of failing silently' do
    payment = pending_qr_payment
    allow_any_instance_of(Spree::Payment).to receive(:void!)
      .and_raise(RuntimeError, 'R2 unreachable while voiding the payment')

    put "/admin/orders/#{order.to_param}/payments/#{payment.to_param}/reject",
        params: { payment: { qr_rejection_reason: 'Amount does not match.' } }

    expect(response).to have_http_status(:redirect)
    expect(payment.reload).to be_pending
    expect(flash[:error]).to include('Could not reject this payment')
    expect(flash[:error]).to include('R2 unreachable while voiding the payment')
  end

  it 'serves the proof image to admins' do
    payment = pending_qr_payment

    get "/admin/orders/#{order.to_param}/payments/#{payment.to_param}/proof"

    expect(response).to have_http_status(:redirect)
    expect(response.headers['Location']).to be_present
  end

  it 'shows Approve/Reject and the proof on the admin order page' do
    pending_qr_payment

    get "/admin/orders/#{order.to_param}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Approve')
    expect(response.body).to include('Reject')
    expect(response.body).to include('Pending verification')
    expect(response.body.scan('alt="Payment screenshot"').size).to eq(1)
  end

  # ── Duplicate-proof and amount checks ──────────────────────────────────

  it 'shows the amount due next to the screenshot and flags a short payment' do
    pending_qr_payment(txn_id: 'TXN-SHORT', amount: order.total - 1)

    get "/admin/orders/#{order.to_param}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(Spree.t(:qr_amount_due))
    expect(response.body).to include(Spree.t(:qr_payment_amount))
    # The amount mismatch warning (a plain substring avoids HTML escaping).
    expect(response.body).to include('does not match the order')
  end

  it 'does not flag a payment that matches the amount due' do
    pending_qr_payment(txn_id: 'TXN-MATCH')

    get "/admin/orders/#{order.to_param}"

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('does not match the order')
  end

  it 'flags a transaction id and screenshot already used on another payment' do
    pending_qr_payment(txn_id: 'TXN-DUP-9')

    other_order = create(:completed_order_with_totals, store: store, currency: 'NPR')
    other = other_order.payments.create!(
      payment_method: qr_method,
      amount: other_order.total,
      response_code: SecureRandom.uuid,
      skip_source_requirement: true
    )
    other.proof_image.attach(
      io: File.open(Rails.root.join('spec/fixtures/files/qr-proof.png')),
      filename: 'qr-proof.png', content_type: 'image/png'
    )
    other.update!(qr_transaction_id: 'TXN-DUP-9')
    other.pend!

    get "/admin/orders/#{order.to_param}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Transaction ID is also used on 1 other payment')
    expect(response.body).to include('Identical screenshot already filed on 1 other payment')
  end

  it 'stays quiet when the transaction id and screenshot are unique' do
    payment = pending_qr_payment(txn_id: 'TXN-ONLY-ONCE')
    # A different screenshot than the duplicate test: no second payment exists,
    # so both checks must come back clean.
    expect(payment.qr_transaction_id_duplicate_count).to eq(0)
    expect(payment.qr_proof_duplicate_count).to eq(0)

    get "/admin/orders/#{order.to_param}"

    expect(response.body).not_to include('is also used on')
    expect(response.body).not_to include('already filed on')
  end
end

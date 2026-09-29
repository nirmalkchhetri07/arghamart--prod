# frozen_string_literal: true

require 'rails_helper'

# Admin review of Manual QR payments: Approve completes a pending payment,
# Reject voids it with a reason, the proof is served to admins, and the order
# page shows the review UI only for Manual QR payments.
RSpec.describe 'Admin Manual QR review', type: :request do
  # Manual QR is NPR-only: teach the test store NPR (markets + legacy column).
  let!(:store_override) do
    store.markets.update_all(currency: 'NPR') if store.respond_to?(:markets)
    store.update!(supported_currencies: 'USD,NPR') if store.has_attribute?(:supported_currencies)
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

  def pending_qr_payment
    order.payments.destroy_all
    payment = order.payments.create!(
      payment_method: qr_method,
      amount: order.reload.total,
      response_code: SecureRandom.uuid,
      skip_source_requirement: true
    )
    payment.proof_image.attach(
      io: File.open(Rails.root.join('spec/fixtures/files/qr-proof.png')),
      filename: 'qr-proof.png', content_type: 'image/png'
    )
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
  end
end

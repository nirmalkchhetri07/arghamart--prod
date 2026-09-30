# frozen_string_literal: true

require 'rails_helper'

# Auto-cancellation of Manual QR orders nobody verified in time: the order is
# canceled (reason `expired`), its shipment is canceled → stock restocked, and
# the pending QR payment is voided with a customer-readable reason.
RSpec.describe Spree::ManualQrExpireOrdersJob, type: :job do
  # Manual QR is NPR-only: teach the test store NPR (markets + legacy column),
  # or `order.cancel!` refuses the transition with "Currency is not supported
  # by this store" when the job re-saves the backdated order.
  let!(:store_override) do
    store.markets.update_all(currency: 'NPR') if store.respond_to?(:markets)
    # update_column, not update!: the shared @default_store object can still
    # hold 'USD,NPR' in memory from a previous example whose transaction was
    # rolled back — Rails then sees no dirty change, skips the UPDATE, and the
    # cancel transition fails with "Currency is not supported by this store".
    store.update_column(:supported_currencies, 'USD,NPR') if store.has_attribute?(:supported_currencies)
    store.reload
  end

  # No currency validation on the order itself (order-dependent under
  # DatabaseCleaner): create it in the store's own currency, then set NPR with
  # update_columns — Spree::Payment validates ManualQr#available_for_order?,
  # which requires order.currency == 'NPR'.
  let(:store) { @default_store || create(:store) }
  let(:payment_method) do
    Spree::PaymentMethod::ManualQr.create!(
      name: 'Manual QR',
      active: true,
      display_on: 'front_end',
      store: store
      # preferred_order_timeout_hours defaults to 24
    )
  end

  # A completed QR order with a pending (unreviewed) payment, backdated so it
  # sits either side of the timeout window.
  def qr_order(completed_hours_ago:, method: payment_method, payment_state: 'pending', order_store: store)
    order = create(:completed_order_with_totals, store: order_store)
    order.update_columns(currency: 'NPR', completed_at: completed_hours_ago.hours.ago)

    payment = order.payments.create!(
      payment_method: method,
      amount: order.total,
      response_code: SecureRandom.uuid,
      skip_source_requirement: true
    )
    payment.proof_image.attach(
      io: File.open(Rails.root.join('spec/fixtures/files/qr-proof.png')),
      filename: 'qr-proof.png', content_type: 'image/png'
    )
    payment.pend!
    payment.complete! if payment_state == 'completed'
    order
  end

  def stock_item_for(order)
    shipment = order.shipments.reload.first
    shipment.stock_location.stock_items.find_by!(variant: order.line_items.first.variant)
  end

  it 'cancels an unverified QR order past the timeout and releases its stock' do
    order = qr_order(completed_hours_ago: 25)
    stock_item = stock_item_for(order)
    on_hand_before = stock_item.count_on_hand
    quantity = order.line_items.sum(:quantity)

    expect { described_class.perform_now }.to change {
      order.reload.state
    }.from('complete').to('canceled')

    # Stock goes back on hand (shipment canceled → manifest restocked).
    expect(stock_item.reload.count_on_hand).to eq(on_hand_before + quantity)
    expect(order.shipments.reload).to all(be_canceled)

    # The pending QR payment is voided with a reason the customer can read.
    payment = order.payments.reload.sole
    expect(payment).to be_void
    expect(payment.qr_status).to eq('rejected')
    expect(payment.qr_rejection_reason).to be_present

    cancellation = order.cancellations.sole
    expect(cancellation.reason).to eq('expired')
    expect(cancellation.restock_items).to be(true)
  end

  it 'leaves an order inside the timeout window alone' do
    order = qr_order(completed_hours_ago: 2)

    described_class.perform_now

    expect(order.reload.state).to eq('complete')
    expect(order.payments.reload.sole).to be_pending
  end

  it 'leaves an order whose QR payment was already verified (approved)' do
    order = qr_order(completed_hours_ago: 25, payment_state: 'completed')

    described_class.perform_now

    expect(order.reload.state).to eq('complete')
    expect(order.payments.reload.sole).to be_completed
  end

  it 'honours a per-method timeout of 0 (disabled)' do
    payment_method.update!(preferred_order_timeout_hours: 0)
    order = qr_order(completed_hours_ago: 100)

    described_class.perform_now

    expect(order.reload.state).to eq('complete')
  end

  it 'honours a custom per-method timeout' do
    payment_method.update!(preferred_order_timeout_hours: 2)
    fresh = qr_order(completed_hours_ago: 3)
    fresh_order = qr_order(completed_hours_ago: 1)

    described_class.perform_now

    expect(fresh.reload.state).to eq('canceled')
    expect(fresh_order.reload.state).to eq('complete')
  end

  it 'does not touch other stores’ QR orders' do
    other_store = create(:store)
    # The job walks every Manual QR method, so disable the other store's own
    # method: only this store's method is live, and its orders must be out of
    # scope for it.
    other_method = Spree::PaymentMethod::ManualQr.create!(
      name: 'Other store QR', active: true, display_on: 'front_end', store: other_store,
      preferred_order_timeout_hours: 0
    )
    other_order = qr_order(
      completed_hours_ago: 48,
      method: other_method,
      order_store: other_store
    )

    described_class.perform_now

    expect(other_order.reload.state).to eq('complete')
    expect(other_order.payments.reload.sole).to be_pending
  end
end

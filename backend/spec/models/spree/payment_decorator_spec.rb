# frozen_string_literal: true

require 'rails_helper'

# Draft orders keep a stale payment_state in stock Spree: Payment#update_order
# and OrderUpdater#update only recompute it for completed orders. The
# after_commit refresh in PaymentDecorator closes that gap.
#
# after_commit never fires inside a transactional test, so this file opts out
# of transactional tests and cleans with truncation instead (restored after).
RSpec.describe 'Payment order-state refresh', type: :model do
  self.use_transactional_tests = false

  before(:context) { DatabaseCleaner.strategy = :truncation }
  after(:context) { DatabaseCleaner.strategy = :transaction }

  let(:store) { @default_store }
  let(:cash_method) do
    create(:check_payment_method, store: store, name: 'Cash (Physical)', auto_capture: false)
  end

  def draft_order_with_cash(amount: nil)
    order = create(:order_with_line_items, store: store)
    order.reload.update_with_updater!
    create(:payment, order: order, payment_method: cash_method,
                     amount: amount || order.reload.total, state: 'checkout')
  end

  it 'marks a fully-paid DRAFT order paid while it is still not complete' do
    payment = draft_order_with_cash
    order = payment.order
    expect(order.state).not_to eq('complete')

    payment.process!
    expect(payment.reload).to be_pending
    expect(order.reload.payment_state).not_to eq('paid')

    payment.capture!

    expect(payment.reload).to be_completed
    expect(order.reload.payment_state).to eq('paid')
    expect(order.state).not_to eq('complete')
  end

  it 're-opens the balance when a completed payment is voided' do
    payment = draft_order_with_cash
    order = payment.order
    payment.capture!
    expect(order.reload.payment_state).to eq('paid')

    payment.void_transaction!

    expect(payment.reload).to be_void
    expect(order.reload.payment_state).to eq('balance_due')
  end

  it 'leaves a pending COD-style payment on balance due (regression)' do
    payment = draft_order_with_cash
    order = payment.order

    payment.process!

    expect(payment.reload).to be_pending
    expect(order.reload.payment_state).not_to eq('paid')
  end
end

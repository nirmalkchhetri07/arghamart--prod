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
    order.reload
    expect(order.payment_total).to eq(order.total)
    expect(order.outstanding_balance).to eq(0)
    expect(order.payment_state).to eq('paid')
    expect(order.state).not_to eq('complete')
  end

  it 'keeps the remaining balance for a partial payment on a draft order' do
    order = create(:order_with_line_items, store: store)
    order.reload.update_with_updater!
    payment_amount = (order.reload.total / 2).round(2)
    payment = create(:payment, order: order, payment_method: cash_method,
                               amount: payment_amount, state: 'checkout')

    payment.capture!

    order.reload
    expect(order.payment_total).to eq(payment_amount)
    expect(order.outstanding_balance).to eq(order.total - payment_amount)
    expect(order.payment_state).to eq('balance_due')
  end

  it 're-opens the balance when a completed payment is voided' do
    payment = draft_order_with_cash
    order = payment.order
    payment.capture!
    order.reload
    expect(order.payment_total).to eq(order.total)
    expect(order.outstanding_balance).to eq(0)
    expect(order.payment_state).to eq('paid')

    payment.void_transaction!

    expect(payment.reload).to be_void
    order.reload
    expect(order.payment_total).to eq(0)
    expect(order.outstanding_balance).to eq(order.total)
    expect(order.payment_state).to eq('balance_due')
  end

  it 'records an overpayment as credit owed on a draft order' do
    order = create(:order_with_line_items, store: store)
    order.reload.update_with_updater!
    payment_amount = order.reload.total + 25
    payment = create(:payment, order: order, payment_method: cash_method,
                               amount: payment_amount, state: 'checkout')

    payment.capture!

    order.reload
    expect(order.payment_total).to eq(payment_amount)
    expect(order.outstanding_balance).to eq(0)
    expect(order.payment_state).to eq('credit_owed')
  end

  it 'leaves a pending COD-style payment on balance due (regression)' do
    payment = draft_order_with_cash
    order = payment.order

    payment.process!

    expect(payment.reload).to be_pending
    order.reload
    expect(order.payment_total).to eq(0)
    expect(order.outstanding_balance).to eq(order.total)
    expect(order.payment_state).to eq('balance_due')
  end
end

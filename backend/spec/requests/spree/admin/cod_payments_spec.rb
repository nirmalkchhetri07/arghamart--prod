# frozen_string_literal: true

require 'rails_helper'

# Cash on Delivery (Spree::PaymentMethod::Check named "Cash on Delivery",
# auto_capture disabled by migration) must stay pending through checkout and
# only complete once cash is collected — automatically on delivery, manually
# via the stock admin Capture action, or explicitly voided on refusal.
RSpec.describe 'Cash on Delivery payments', type: :request do
  let(:store) { @default_store }
  let(:admin_user) { create(:admin_user) }
  let(:cod_method) do
    create(:check_payment_method, store: store, name: 'Cash on Delivery', auto_capture: false)
  end
  let(:order) { create(:shipped_order, store: store) }
  let(:shipment) { order.shipments.first }

  # A shipped order whose ONLY payment is a pending COD payment for the full
  # total — mirrors a real COD checkout after the auto-capture fix. Totals are
  # re-read after the updater because recalculation can shift factory totals.
  def cod_order_with_pending_payment
    order.payments.destroy_all
    order.reload.update_with_updater!
    payment = create(:payment, order: order, payment_method: cod_method,
                               amount: order.reload.total, state: 'pending')
    order.reload.update_with_updater!
    payment.reload
  end

  describe 'checkout behavior' do
    it 'leaves a COD payment pending (not completed) when processed' do
      order.payments.destroy_all
      payment = create(:payment, order: order, payment_method: cod_method,
                                 amount: order.reload.total, state: 'checkout')

      payment.process!

      expect(payment.reload).to be_pending
      expect(payment).not_to be_completed
    end

    it 'leaves the order unpaid (balance_due, not paid) with only a pending COD payment' do
      payment = cod_order_with_pending_payment

      expect(payment).to be_pending
      expect(order.reload.payment_state).to eq('balance_due')
    end
  end

  describe 'mark_as_delivered!' do
    it 'auto-captures the pending COD payment and marks the order paid' do
      payment = cod_order_with_pending_payment

      shipment.mark_as_delivered!

      expect(payment.reload).to be_completed
      expect(order.reload.payment_state).to eq('paid')
      expect(shipment.reload).to be_delivered
    end

    it 'leaves already-completed COD payments untouched' do
      order.payments.destroy_all
      payment = create(:payment, order: order, payment_method: cod_method,
                                 amount: order.reload.total, state: 'completed')

      expect { shipment.mark_as_delivered! }.not_to(change { payment.reload.updated_at })
      expect(payment.reload).to be_completed
    end

    it 'leaves non-COD (gateway) pending payments untouched' do
      order.payments.destroy_all
      gateway_method = create(:credit_card_payment_method, store: store)
      payment = create(:payment, order: order, payment_method: gateway_method,
                                 amount: order.total, state: 'pending')

      shipment.mark_as_delivered!

      expect(payment.reload).to be_pending
    end
  end

  describe 'admin manual actions (stock Capture / Void)' do
    before { login_as(admin_user, scope: :admin_user) }

    def payment_path(payment, action)
      "/admin/orders/#{order.to_param}/payments/#{payment.to_param}/#{action}"
    end

    it 'confirms cash collected via Capture independently of delivery' do
      payment = cod_order_with_pending_payment

      put payment_path(payment, 'capture')

      expect(response).to have_http_status(:redirect)
      expect(payment.reload).to be_completed
      expect(order.reload.payment_state).to eq('paid')
      expect(shipment.reload.delivered_at).to be_nil
    end

    it 'voids a refused COD payment without breaking the order' do
      payment = cod_order_with_pending_payment

      put payment_path(payment, 'void')

      expect(response).to have_http_status(:redirect)
      expect(payment.reload).to be_void
      expect(order.reload.state).to eq('complete')
    end

    it 'shows Capture and Void actions for a pending COD payment' do
      cod_order_with_pending_payment

      get "/admin/orders/#{order.to_param}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Capture')
      expect(response.body).to include('Void')
    end
  end
end

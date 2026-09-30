# frozen_string_literal: true

module Spree
  # Auto-cancels Manual QR orders whose payment nobody verified in time, so
  # unpaid QR orders can't hold stock hostage forever.
  #
  # Scheduled from config/recurring.yml (every 15 minutes). Each Manual QR
  # method carries its own `order_timeout_hours` preference (default 24,
  # 0 disables it), measured from `Spree::Order#completed_at`.
  #
  # Spree's cancel service does the heavy lifting (Spree::Orders::Cancel):
  #   * records an Spree::OrderCancellation with reason `expired`;
  #   * flips the order to `canceled`, whose `after_cancel` cancels every
  #     shipment → `manifest_restock` puts the units back on hand (the
  #     `restock_items: true` flag documents that intent for the audit row);
  #   * voids the still-pending QR payment, so the customer's order page
  #     shows the payment as rejected rather than silently pending.
  #
  # Orders already shipped are skipped by Spree's `allow_cancel?` guard —
  # the job logs those instead of force-canceling fulfilled stock.
  class ManualQrExpireOrdersJob < Spree::BaseJob
    def perform
      Spree::PaymentMethod::ManualQr.find_each do |method|
        hours = method.preferred_order_timeout_hours.to_i
        next unless hours.positive?

        expire_orders_for(method, hours)
      end
    end

    private

    def expire_orders_for(method, hours)
      scope = Spree::Order.
        where(store_id: method.store_id).
        where(state: 'complete').
        where(canceled_at: nil).
        where('spree_orders.completed_at < ?', hours.hours.ago).
        where(id: Spree::Payment.where(payment_method_id: method.id, state: 'pending').select(:order_id))

      scope.find_each do |order|
        cancel_expired_qr_order(order, hours)
      end
    end

    def cancel_expired_qr_order(order, hours)
      result = Spree.order_cancel_service.call(
        order: order,
        canceler: nil,
        canceled_at: Time.current,
        reason: 'expired',
        note: "Manual QR payment not verified within #{hours} hours",
        restock_items: true,
        notify_customer: true
      )

      if result.success?
        annotate_voided_qr_payments(order, hours)
        Rails.logger.info("[manual_qr] auto-canceled #{order.number}: QR payment unverified after #{hours}h")
      else
        Rails.logger.warn(
          "[manual_qr] could not auto-cancel #{order.number} " \
          "(state=#{order.state} shipment_state=#{order.shipment_state})"
        )
      end
    end

    # Spree voids the pending payment generically; give the customer a reason
    # they can read (the storefront renders `qr_rejection_reason` next to the
    # rejected status). Already-annotated payments keep their own reason.
    def annotate_voided_qr_payments(order, hours)
      order.payments.select(&:manual_qr?).select(&:void?).each do |payment|
        next if payment.qr_rejection_reason.present?

        payment.update_column(
          :qr_rejection_reason,
          Spree.t('manual_qr.expired_rejection_reason', hours: hours)
        )
      end
    end
  end
end

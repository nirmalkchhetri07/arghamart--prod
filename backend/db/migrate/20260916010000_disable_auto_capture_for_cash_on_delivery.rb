# frozen_string_literal: true

# Cash on Delivery must NOT auto-complete at checkout: the courier collects
# cash at the door, so the payment stays pending until delivery (captured
# automatically by Spree::ShipmentDecorator#mark_as_delivered!) or manual
# capture in the admin.
#
# Root cause: Spree::PaymentMethod::Check#auto_capture? falls back to the
# global Spree::Config[:auto_capture] (true) when the record-level flag is
# nil, so process_payments! ran `purchase` (completed) instead of
# `authorize` (pending) at order completion. Setting the record flag to
# false switches this method to authorize-then-capture without touching the
# global default or any other gateway (eSewa/Khalti unaffected).
class DisableAutoCaptureForCashOnDelivery < ActiveRecord::Migration[8.1]
  def up
    Spree::PaymentMethod::Check.where(name: 'Cash on Delivery').update_all(auto_capture: false)
  end

  def down
    Spree::PaymentMethod::Check.where(name: 'Cash on Delivery').update_all(auto_capture: nil)
  end
end

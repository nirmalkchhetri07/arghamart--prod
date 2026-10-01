# frozen_string_literal: true

# "Cash (Physical)" payment method for admin-recorded in-person tenders
# (see Spree::OfflinePayments::Record). A Check-type method like the
# existing Cash on Delivery: simulated gateway, capture/void, no source.
#
# - `display_on: 'back_end'` — admin only, never leaks into storefront
#   checkout (`collect_backend_payment_methods` picks it up).
# - `auto_capture: false` — like COD, the payment stays pending until the
#   recorder captures it explicitly (see adjustment: cash is captured
#   immediately inside the recorder, never left pending).
# - One row per store (methods belong to a store).
#
# Idempotent: skips stores that already have it; safe to re-run.
# Ownership is tagged by migration 000007. The follow-up migration exists
# because this migration may already be recorded as applied in deployed DBs.
class CreateCashPhysicalPaymentMethod < ActiveRecord::Migration[8.1]
  METHOD_NAME = 'Cash (Physical)'
  OWNERSHIP_KEY = 'arghamart_cash_physical_payment_method'
  OWNERSHIP_VALUE = '20261001000007'

  def up
    Spree::Store.find_each do |store|
      next if Spree::PaymentMethod.with_deleted.where(store: store, name: METHOD_NAME).exists?

      Spree::PaymentMethod::Check.create!(
        store: store,
        name: METHOD_NAME,
        description: 'Cash received in person (store / delivery handover). Recorded by staff in Admin.',
        active: true,
        display_on: 'back_end',
        auto_capture: false,
        private_metadata: { OWNERSHIP_KEY => OWNERSHIP_VALUE }
      )
    end
  end

  def down
    Spree::PaymentMethod::Check.where(name: METHOD_NAME).
      where("private_metadata ->> '#{OWNERSHIP_KEY}' = ?", OWNERSHIP_VALUE).find_each do |payment_method|
        next if Spree::Payment.where(payment_method_id: payment_method.id).exists?

        payment_method.destroy!
      end
  end
end

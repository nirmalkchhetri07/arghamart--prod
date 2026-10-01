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
# Reversible: `down` removes only rows this migration owns (by name).
class CreateCashPhysicalPaymentMethod < ActiveRecord::Migration[8.1]
  METHOD_NAME = 'Cash (Physical)'

  def up
    Spree::Store.find_each do |store|
      next if Spree::PaymentMethod::Check.where(store: store, name: METHOD_NAME).exists?

      Spree::PaymentMethod::Check.create!(
        store: store,
        name: METHOD_NAME,
        description: 'Cash received in person (store / delivery handover). Recorded by staff in Admin.',
        active: true,
        display_on: 'back_end',
        auto_capture: false
      )
    end
  end

  def down
    Spree::PaymentMethod::Check.where(name: METHOD_NAME).destroy_all
  end
end

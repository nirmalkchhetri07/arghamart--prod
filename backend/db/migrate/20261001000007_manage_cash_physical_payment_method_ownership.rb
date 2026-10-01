# frozen_string_literal: true

# Follow-up to 20261001000006_create_cash_physical_payment_method.
# That migration has shipped, so its behavior is not changed here. This
# migration tags only rows matching its original signature, creates a tagged
# method for stores that still lack one, and safely removes only tagged,
# unused methods when rolled back.
class ManageCashPhysicalPaymentMethodOwnership < ActiveRecord::Migration[8.1]
  METHOD_NAME = 'Cash (Physical)'
  LEGACY_DESCRIPTION = 'Cash received in person (store / delivery handover). Recorded by staff in Admin.'
  OWNERSHIP_KEY = 'arghamart_cash_physical_payment_method'
  OWNERSHIP_VALUE = '20261001000007'

  def up
    mark_methods_created_by_previous_migration

    Spree::Store.find_each do |store|
      next if Spree::PaymentMethod.with_deleted.where(store: store, name: METHOD_NAME).exists?

      Spree::PaymentMethod::Check.create!(
        store: store,
        name: METHOD_NAME,
        description: LEGACY_DESCRIPTION,
        active: true,
        display_on: 'back_end',
        auto_capture: false,
        private_metadata: { OWNERSHIP_KEY => OWNERSHIP_VALUE }
      )
    end
  end

  def down
    owned_methods.find_each do |payment_method|
      next if Spree::Payment.where(payment_method_id: payment_method.id).exists?

      payment_method.destroy!
    end
  end

  private

  # Migration 000006 did not record ownership. Its exact generated description
  # and configuration provide the narrowest available signature for tagging
  # those legacy rows while leaving differently configured methods untouched.
  def mark_methods_created_by_previous_migration
    Spree::PaymentMethod::Check.with_deleted.where(
      name: METHOD_NAME,
      description: LEGACY_DESCRIPTION,
      display_on: 'back_end',
      auto_capture: false
    ).find_each do |payment_method|
      metadata = (payment_method.private_metadata || {}).stringify_keys
      next if metadata[OWNERSHIP_KEY] == OWNERSHIP_VALUE

      payment_method.update!(private_metadata: metadata.merge(OWNERSHIP_KEY => OWNERSHIP_VALUE))
    end
  end

  def owned_methods
    Spree::PaymentMethod::Check.with_deleted.where(
      name: METHOD_NAME
    ).where("private_metadata ->> '#{OWNERSHIP_KEY}' = ?", OWNERSHIP_VALUE)
  end
end

# frozen_string_literal: true

# Offline (in-person) payment details for admin-recorded cash / on-the-spot
# QR / bank-transfer tenders (see Spree::OfflinePayments::Record).
#
# One row per Spree::Payment (`payment_id` unique): the payment's own
# `amount` stores what was APPLIED to the order
# (min(amount_received, balance_due)); the overpayment handed back to the
# customer lives here as `change_returned`. `pay_later` marks orders the
# admin explicitly released to fulfillment with a balance outstanding.
#
# Additive only: creates one table, touches no existing table or data.
# Reversible via `change`.
class CreateOfflinePaymentDetails < ActiveRecord::Migration[8.1]
  def change
    create_table :offline_payment_details do |t|
      t.references :payment, null: false, foreign_key: { to_table: :spree_payments },
                             index: { unique: true, name: :index_offline_payment_details_on_payment_id }
      t.decimal :amount_received, precision: 10, scale: 2, null: false
      t.decimal :change_returned, precision: 10, scale: 2, null: false, default: '0.0'
      t.references :received_by, null: false, foreign_key: { to_table: :spree_admin_users },
                                index: { name: :index_offline_payment_details_on_received_by_id }
      t.datetime :received_at, null: false
      t.boolean :pay_later, null: false, default: false
      t.text :note

      t.timestamps
    end
  end
end

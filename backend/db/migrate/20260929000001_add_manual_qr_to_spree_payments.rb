# frozen_string_literal: true

# Manual QR payments (Spree::PaymentMethod::ManualQr): the customer pays in
# their own banking/wallet app and uploads a screenshot as proof. The proof
# itself lives in Active Storage (attached to Spree::Payment, no column
# needed); these columns hold the review metadata.
class AddManualQrToSpreePayments < ActiveRecord::Migration[8.1]
  def change
    add_column :spree_payments, :qr_transaction_id, :string
    add_column :spree_payments, :qr_rejection_reason, :text
  end
end

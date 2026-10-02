# frozen_string_literal: true

class AddNcmFieldsToSpreeShipments < ActiveRecord::Migration[8.1]
  def change
    add_column :spree_shipments, :ncm_order_id, :string
    add_column :spree_shipments, :ncm_status, :string
    add_column :spree_shipments, :ncm_sent_at, :datetime
    add_index :spree_shipments, :ncm_order_id, unique: true, where: 'ncm_order_id IS NOT NULL'
  end
end

# Node equivalent: database migration that stores carrier identifiers and status.
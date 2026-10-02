# frozen_string_literal: true

class ExpandNcmDeliveryConfiguration < ActiveRecord::Migration[8.1]
  def change
    change_table :spree_delivery_partners, bulk: true do |t|
      t.string :default_delivery_type, null: false, default: 'Door2Door'
      t.string :default_origin_branch, null: false, default: 'BUTW1'
      t.string :default_destination_policy, null: false, default: 'mapped'
      t.string :default_package_type, null: false, default: 'Parcel'
      t.text :package_template, null: false, default: '{items}'
      t.text :instruction_template, null: false, default: '{customer_note}'
      t.string :shop_location, null: false, default: 'Sandhikharka, Arghakhanchi'
      t.decimal :fallback_weight_kg, precision: 8, scale: 3, null: false, default: 1
      t.boolean :include_delivery_charge_in_cod, null: false, default: true
    end

    create_table :spree_ncm_branches do |t|
      t.string :name, null: false
      t.string :code, null: false
      t.references :district, index: true
      t.string :municipality
      t.boolean :active, null: false, default: true
      t.integer :nearest_rank
      t.timestamps
    end
    add_index :spree_ncm_branches, :code, unique: true
    add_index :spree_ncm_branches, %i[district_id municipality active], name: 'index_ncm_branches_on_location'

    create_table :spree_ncm_branch_mappings do |t|
      t.references :branch, null: false, foreign_key: { to_table: :spree_ncm_branches }
      t.references :district, null: false, foreign_key: { to_table: :spree_districts }
      t.string :municipality
      t.string :source, null: false, default: 'admin'
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :spree_ncm_branch_mappings, %i[district_id municipality active], name: 'index_ncm_mappings_on_location'

    create_table :spree_ncm_delivery_rates do |t|
      t.references :origin_branch, null: false, foreign_key: { to_table: :spree_ncm_branches }
      t.references :destination_branch, null: false, foreign_key: { to_table: :spree_ncm_branches }
      t.string :delivery_type, null: false
      t.decimal :base_rate, precision: 10, scale: 2, null: false
      t.decimal :per_kg_rate, precision: 10, scale: 2, null: false, default: 0
      t.string :currency, null: false, default: 'NPR'
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :spree_ncm_delivery_rates, %i[origin_branch_id destination_branch_id delivery_type],
              unique: true, name: 'index_ncm_rates_on_route_and_type'

    change_table :spree_districts, bulk: true do |t|
      t.jsonb :name_aliases, null: false, default: []
    end

    change_table :spree_addresses, bulk: true do |t|
      t.string :phone2
    end

    change_table :spree_products, bulk: true do |t|
      t.string :ncm_handling, null: false, default: 'Non-Fragile'
    end

    change_table :spree_taxons, bulk: true do |t|
      t.string :ncm_handling
    end

    change_table :spree_orders, bulk: true do |t|
      t.string :ncm_order_id
      t.string :ncm_status
      t.datetime :ncm_sent_at
      t.decimal :ncm_cod_amount, precision: 10, scale: 2
      t.decimal :ncm_delivery_charge, precision: 10, scale: 2
    end
    add_index :spree_orders, :ncm_order_id, unique: true, where: 'ncm_order_id IS NOT NULL'

    change_table :spree_shipments, bulk: true do |t|
      t.string :ncm_tracking_id
      t.decimal :ncm_delivery_charge, precision: 10, scale: 2
      t.string :ncm_delivery_type
      t.string :ncm_origin_branch
      t.string :ncm_destination_branch
      t.string :ncm_package_type
      t.text :ncm_package_override
      t.text :ncm_instruction_override
      t.string :ncm_branch_resolution
      t.text :ncm_review_reason
      t.text :ncm_failure_message
    end

    change_table :spree_payments, bulk: true do |t|
      t.decimal :qr_received_amount, precision: 10, scale: 2
      t.bigint :qr_received_by_id
      t.datetime :qr_received_at
    end
    add_index :spree_payments, :qr_received_by_id
  end
end

# Node equivalent: a reversible database migration that adds NCM configuration, routing, shipment tracking, and QR receipt audit fields.
# frozen_string_literal: true

class CreateSpreeDeliveryPartners < ActiveRecord::Migration[8.1]
  def change
    create_table :spree_delivery_partners do |t|
      t.string :provider, null: false
      t.string :environment, null: false, default: 'sandbox'
      t.text :sandbox_api_token
      t.text :production_api_token
      t.string :default_pickup_branch
      t.string :webhook_secret, null: false
      t.jsonb :branch_options, null: false, default: []
      t.boolean :active, null: false, default: false
      t.timestamps
    end

    add_index :spree_delivery_partners, :provider, unique: true
    add_index :spree_delivery_partners, :active,
              unique: true,
              where: 'active = TRUE',
              name: 'index_spree_delivery_partners_on_active'
  end
end

# Node equivalent: database migration that creates the delivery-partner settings table.
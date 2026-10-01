# frozen_string_literal: true

# Nepal-specific delivery geography for ArghaMart.
#
# spree_provinces: the 7 provinces of Nepal (static reference data).
# spree_districts: the 77 districts, each belonging to a province, with an
#   active flag (inactive districts are hidden from the storefront dropdown)
#   and a shipping_fee in NPR (decimal, defaults to 0 = "no fee set yet").
class CreateSpreeProvincesAndDistricts < ActiveRecord::Migration[8.1]
  def change
    create_table :spree_provinces do |t|
      t.string :name, null: false
      t.string :code, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :spree_provinces, :name, unique: true
    add_index :spree_provinces, :code, unique: true

    create_table :spree_districts do |t|
      t.string :name, null: false
      t.references :province, null: false, foreign_key: { to_table: :spree_provinces }
      t.decimal :shipping_fee, precision: 10, scale: 2, default: 0, null: false
      t.boolean :active, default: true, null: false
      t.timestamps
    end
    add_index :spree_districts, %i[province_id name], unique: true
    add_index :spree_districts, :active
  end
end

# frozen_string_literal: true

# Links a Spree address to its Nepal province/district.
#
# Both columns are nullable so existing orders and saved addresses keep
# working without a backfill. New Nepal checkout addresses fill both;
# validation (see Spree::AddressDecorator) only enforces the
# district-belongs-to-province rule when both are present.
class AddProvinceAndDistrictToSpreeAddresses < ActiveRecord::Migration[8.1]
  def change
    add_reference :spree_addresses, :province, foreign_key: { to_table: :spree_provinces }
    add_reference :spree_addresses, :district, foreign_key: { to_table: :spree_districts }
  end
end

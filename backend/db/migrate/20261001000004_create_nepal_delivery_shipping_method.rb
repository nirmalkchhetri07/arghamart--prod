# frozen_string_literal: true

# Creates the "Nepal Delivery" shipping method backed by
# Spree::Calculator::Shipping::DistrictShipping.
#
# Additive only: runs only when no DistrictShipping-backed method exists, and
# never touches the existing "Standard" (FlatRate) method. Zones and shipping
# categories are copied from the first existing method so the new method is
# available everywhere the store already ships; falls back to all zones +
# the Default category on a fresh install.
class CreateNepalDeliveryShippingMethod < ActiveRecord::Migration[8.1]
  def up
    return if Spree::ShippingMethod.joins(:calculator).
              where(spree_calculators: { type: 'Spree::Calculator::Shipping::DistrictShipping' }).
              exists?

    calculator = Spree::Calculator::Shipping::DistrictShipping.create!(
      preferred_default_fee: 0,
      preferred_currency: Spree::Store.default&.default_currency || 'NPR'
    )

    template = Spree::ShippingMethod.first
    zones = template&.zones.presence || Spree::Zone.all
    categories = template&.shipping_categories.presence ||
      [Spree::ShippingCategory.find_or_create_by!(name: 'Default')]

    Spree::ShippingMethod.create!(
      name: 'Nepal Delivery',
      display_on: 'both',
      calculator: calculator,
      zones: zones,
      shipping_categories: categories
    )
  end

  def down
    Spree::ShippingMethod.joins(:calculator).
      where(name: 'Nepal Delivery',
            spree_calculators: { type: 'Spree::Calculator::Shipping::DistrictShipping' }).
      destroy_all
  end
end

# frozen_string_literal: true

# Independent "Delivered" tracking layered on top of Spree's shipment state
# machine. Deliberately NOT a new `state` value — spree_shipments.state
# (pending/ready/shipped) is depended on by shipping calculators, inventory
# units, and order completion logic throughout Spree core.
class AddDeliveredAtToSpreeShipments < ActiveRecord::Migration[7.2]
  def change
    add_column :spree_shipments, :delivered_at, :datetime
  end
end

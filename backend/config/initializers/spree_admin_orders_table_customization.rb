# frozen_string_literal: true

# Adds the "Delivered" column + filter to the admin orders table, alongside
# the existing shipment_state column/filter. Staff can combine the
# "Shipment state = Shipped" filter with "Delivered is empty" to find
# shipped-but-not-yet-delivered orders.
Rails.application.config.after_initialize do
  Spree.admin.tables.orders.add :delivered,
                                label: :delivered,
                                type: :custom,
                                sortable: false,
                                filterable: true,
                                filter_type: :datetime,
                                default: false,
                                position: 65,
                                partial: 'spree/admin/tables/columns/order_delivered',
                                ransack_attribute: 'shipments_delivered_at',
                                operators: %i[null not_null]
end

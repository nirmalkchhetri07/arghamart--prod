# frozen_string_literal: true

class AddNcmCodAmountToSpreeShipments < ActiveRecord::Migration[8.1]
  def change
    add_column :spree_shipments, :ncm_cod_amount, :decimal, precision: 10, scale: 2
  end
end

# Node equivalent: a reversible database migration that stores the COD snapshot sent for each shipment.
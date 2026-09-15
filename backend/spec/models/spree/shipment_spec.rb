# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spree::Shipment, type: :model do
  let(:store) { @default_store }

  describe '#delivered?' do
    it 'is false when delivered_at is not set' do
      shipment = create(:shipped_order, store: store).shipments.first

      expect(shipment.delivered?).to be(false)
    end

    it 'is true when delivered_at is set' do
      shipment = create(:shipped_order, store: store).shipments.first
      shipment.mark_as_delivered!

      expect(shipment.reload.delivered?).to be(true)
    end
  end

  describe '#mark_as_delivered!' do
    it 'sets delivered_at on a shipped shipment' do
      shipment = create(:shipped_order, store: store).shipments.first

      expect { shipment.mark_as_delivered! }.
        to change { shipment.reload.delivered_at }.from(nil)
      expect(shipment.delivered?).to be(true)
    end

    it 'does not change the shipment state' do
      shipment = create(:shipped_order, store: store).shipments.first

      shipment.mark_as_delivered!

      expect(shipment.reload.state).to eq('shipped')
    end

    it 'raises on a shipment that is not shipped' do
      shipment = create(:order_ready_to_ship, store: store).shipments.first

      expect { shipment.mark_as_delivered! }.
        to raise_error(Spree::ShipmentDecorator::NotShippedError)
      expect(shipment.reload.delivered_at).to be_nil
    end
  end

  describe 'scopes' do
    it 'finds delivered and undelivered shipments' do
      delivered = create(:shipped_order, store: store).shipments.first
      undelivered = create(:shipped_order, store: store).shipments.first
      delivered.mark_as_delivered!

      expect(Spree::Shipment.delivered).to include(delivered)
      expect(Spree::Shipment.delivered).not_to include(undelivered)
      expect(Spree::Shipment.undelivered).to include(undelivered)
      expect(Spree::Shipment.undelivered).not_to include(delivered)
    end
  end
end

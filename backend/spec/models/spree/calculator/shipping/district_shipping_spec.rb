# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spree::Calculator::Shipping::DistrictShipping, type: :model do
  let(:store) { @default_store }

  before do
    Spree::NepalGeography.seed!
  end

  let(:bagmati) { Spree::Province.find_by!(code: 'BAGMATI') }
  let(:kathmandu) { Spree::District.find_by!(name: 'Kathmandu') }
  let(:country) { Spree::Country.find_by(iso: 'NP') || create(:country, iso: 'NP', iso3: 'NPL', name: 'Nepal') }

  def order_with_district(district, fee: nil)
    district.update!(shipping_fee: fee) unless fee.nil?
    address = create(
      :address,
      country: country,
      province: district&.province,
      district: district,
      phone: '9841234567'
    )
    order = create(:order, store: store)
    order.update!(ship_address: address)
    order
  end

  describe '#compute_package' do
    it 'returns the district fee' do
      kathmandu.update!(shipping_fee: 150, active: true)
      order = order_with_district(kathmandu)
      package = Spree::Stock::Package.new(Spree::StockLocation.first)
      allow(package).to receive(:order).and_return(order)

      calculator = described_class.new(preferred_default_fee: 99)

      expect(calculator.compute(package).to_f).to eq(150)
    end

    it 'falls back to default_fee when the district has no fee configured' do
      kathmandu.update!(shipping_fee: 0, active: true)
      order = order_with_district(kathmandu)
      package = Spree::Stock::Package.new(Spree::StockLocation.first)
      allow(package).to receive(:order).and_return(order)

      calculator = described_class.new(preferred_default_fee: 120)

      expect(calculator.compute(package).to_f).to eq(120)
    end

    it 'falls back when the district is inactive' do
      kathmandu.update!(shipping_fee: 200, active: false)
      order = order_with_district(kathmandu)
      package = Spree::Stock::Package.new(Spree::StockLocation.first)
      allow(package).to receive(:order).and_return(order)

      calculator = described_class.new(preferred_default_fee: 80)

      expect(calculator.compute(package).to_f).to eq(80)
    end

    it 'falls back when the order has no district' do
      address = create(:address, country: country, phone: '9841234567')
      order = create(:order, store: store)
      order.update!(ship_address: address)
      package = Spree::Stock::Package.new(Spree::StockLocation.first)
      allow(package).to receive(:order).and_return(order)

      calculator = described_class.new(preferred_default_fee: 50)

      expect(calculator.compute(package).to_f).to eq(50)
    end

    it 'never raises without an order' do
      package = Spree::Stock::Package.new(Spree::StockLocation.first)
      allow(package).to receive(:order).and_return(nil)

      calculator = described_class.new(preferred_default_fee: 60)

      expect { calculator.compute(package) }.not_to raise_error
      expect(calculator.compute(package).to_f).to eq(60)
    end
  end
end

# frozen_string_literal: true

# Node equivalent: RSpec service tests for the NCM payload builder.
require 'rails_helper'

RSpec.describe Ncm::PayloadBuilder do
  let!(:partner) do
    create(:delivery_partner, active: true, default_pickup_branch: 'BUTWAL').tap do |record|
      record.update!(default_origin_branch: 'BUTW1', package_template: '{items}',
                     instruction_template: 'Order {order_number}. {customer_note} Call before delivery.')
    end
  end
  let!(:province) { create(:nepali_province) }
  let!(:district) { create(:nepali_district, province: province, name: 'Arghakhanchi') }
  let(:order) { create(:order_ready_to_ship) }
  let(:shipment) { order.shipments.first }
  let(:nepal) { Spree::Country.find_by(iso: 'NP') || create(:country, iso: 'NP', iso3: 'NPL', name: 'Nepal') }

  before do
    Ncm::BranchCatalog.ensure!
    district.update!(ncm_branch: 'BUTWAL')
    shipment.order.ship_address.update!(
      country: nepal,
      province: province,
      district: district,
      firstname: 'Nirmal',
      lastname: 'Khadka',
      city: 'Sandhikharka',
      address1: 'Main Road',
      phone: '9841234567',
      phone2: '9801234567'
    )
    shipment.inventory_units.first.variant.update!(weight: BigDecimal('1.25'))
    order.update!(customer_note: 'Leave at reception')
    Spree::NcmDeliveryRate.create!(
      origin_branch: Spree::NcmBranch.find_by!(code: 'BUTW1'),
      destination_branch: Spree::NcmBranch.find_by!(code: 'BUTW1'),
      delivery_type: 'Door2Door',
      base_rate: 75,
      per_kg_rate: 10
    )
  end

  it 'uses the numeric Spree id and the shipping address for carrier identity' do
    payload = described_class.new(shipment:, partner:).call

    expect(payload[:vref_id]).to eq(order.id.to_s)
    expect(payload[:name]).to eq('Nirmal Khadka')
    expect(payload[:name]).not_to include(order.email.to_s)
    expect(payload[:phone]).to eq('9841234567')
    expect(payload[:phone2]).to eq('9801234567')
  end

  it 'uses measured variant weight and sends configured handling and instructions' do
    shipment.inventory_units.first.variant.product.update!(ncm_handling: 'Fragile')

    payload = described_class.new(shipment:, partner:).call

    expect(payload[:weight]).to eq((BigDecimal('1.25') * shipment.inventory_units.first.quantity).to_s('F'))
    expect(payload[:handling]).to eq('Fragile')
    expect(payload[:instruction]).to include("Order #{order.number}")
    expect(payload[:instruction]).to include('Leave at reception')
    expect(payload[:package]).to include(shipment.inventory_units.first.variant.product.name)
  end
end
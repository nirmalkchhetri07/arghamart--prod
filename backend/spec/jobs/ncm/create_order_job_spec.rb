# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ncm::CreateOrderJob, type: :job do
  let!(:partner) { create(:delivery_partner, active: true, default_pickup_branch: 'BUTWAL') }
  let!(:province) { create(:nepali_province) }
  let!(:district) { create(:nepali_district, province: province, ncm_branch: 'BUTWAL') }
  let(:order) { create(:order_ready_to_ship) }
  let(:shipment) { order.shipments.first }
  let(:nepal) { Spree::Country.find_by(iso: 'NP') || create(:country, iso: 'NP', iso3: 'NPL', name: 'Nepal') }
  let(:client) { instance_double(Ncm::Client) }

  before do
    shipment.order.ship_address.update!(country: nepal, district: district, phone: '9841234567')
    allow(Ncm::Client).to receive(:new).and_return(client)
  end

  it 'creates the NCM order and stores the carrier reference' do
    allow(client).to receive(:create_order).and_return({ 'orderid' => 43_150_625 })

    expect {
      described_class.perform_now(shipment.id)
    }.not_to raise_error

    expect(client).to have_received(:create_order).with(hash_including(branch: 'BUTWAL', fbranch: 'BUTWAL'))
    shipment.reload
    expect(shipment.ncm_order_id).to eq('43150625')
    expect(shipment.ncm_status).to eq('Pickup Order Created')
    expect(shipment.ncm_sent_at).to be_present
  end

  it 'does not call NCM when the shipment was already sent' do
    shipment.update_columns(ncm_order_id: '43150625', ncm_sent_at: Time.current, ncm_status: 'Pickup Order Created')
    allow(client).to receive(:create_order)

    described_class.perform_now(shipment.id)

    expect(client).not_to have_received(:create_order)
  end

  it 'raises when the district has no NCM branch mapping' do
    shipment.order.ship_address.update!(district: nil)
    allow(client).to receive(:create_order)

    expect {
      described_class.perform_now(shipment.id)
    }.to raise_error(ArgumentError, /no NCM branch mapping/)

    expect(client).not_to have_received(:create_order)
  end
end

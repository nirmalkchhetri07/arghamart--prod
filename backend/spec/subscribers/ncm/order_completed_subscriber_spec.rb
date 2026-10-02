# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ncm::OrderCompletedSubscriber do
  include ActiveJob::TestHelper

  let!(:partner) { create(:delivery_partner, active: true, default_pickup_branch: 'Kathmandu') }
  let!(:province) { create(:nepali_province) }
  let!(:district) { create(:nepali_district, province: province, ncm_branch: 'Kathmandu') }
  let(:order) { create(:order_ready_to_ship) }
  let(:shipment) { order.shipments.first }
  let(:nepal) { Spree::Country.find_by(iso: 'NP') || create(:country, iso: 'NP', iso3: 'NPL', name: 'Nepal') }

  before do
    shipment.order.shipping_address.update!(country: nepal, district: district, phone: '9841234567')
    clear_enqueued_jobs
  end

  it 'queues NCM creation for each completed order shipment' do
    event = Struct.new(:payload).new({ 'id' => order.prefixed_id })

    expect {
      described_class.new.handle(event)
    }.to have_enqueued_job(Ncm::CreateOrderJob).with(shipment.id)
  end

  it 'does not queue when the shipment has no NCM branch mapping' do
    shipment.order.shipping_address.update!(district: nil)
    event = Struct.new(:payload).new({ 'id' => order.prefixed_id })

    expect {
      described_class.new.handle(event)
    }.not_to have_enqueued_job(Ncm::CreateOrderJob)
  end
end
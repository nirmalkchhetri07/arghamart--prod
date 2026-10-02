# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin NCM dispatch', type: :request do
  include ActiveJob::TestHelper

  let!(:partner) { create(:delivery_partner, active: true, default_pickup_branch: 'Kathmandu') }
  let!(:province) { create(:nepali_province) }
  let!(:district) { create(:nepali_district, province: province, ncm_branch: 'Kathmandu') }
  let(:order) { create(:order_ready_to_ship) }
  let(:shipment) { order.shipments.first }
  let(:nepal) { Spree::Country.find_by(iso: 'NP') || create(:country, iso: 'NP', iso3: 'NPL', name: 'Nepal') }

  before do
    login_as(create(:admin_user), scope: :admin_user)
    shipment.order.shipping_address.update!(country: nepal, district: district, phone: '9841234567')
    clear_enqueued_jobs
  end

  it 'renders the delivery partner Save button with its translation' do
    get '/admin/delivery_partners/ncm/edit'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Save')
    expect(response.body).to include('Delivery Partners')
    expect(response.body).to include('Configure Nepal Can Move')
    expect(response.body).not_to include('translation_missing')
  end

  it 'queues NCM only through the explicit shipment action' do
    expect do
      post "/admin/orders/#{order.to_param}/shipments/#{shipment.to_param}/send_to_ncm"
    end.to have_enqueued_job(Ncm::CreateOrderJob).with(shipment.id)

    expect(response).to have_http_status(:redirect)
  end
end

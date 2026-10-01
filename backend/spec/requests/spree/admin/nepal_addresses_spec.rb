# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Nepal addresses', type: :request do
  let(:admin_user) { create(:admin_user) }

  before do
    login_as(admin_user, scope: :admin_user)
    Spree::NepalGeography.seed!
  end

  let(:bagmati) { Spree::Province.find_by!(code: 'BAGMATI') }
  let(:kathmandu) { Spree::District.find_by!(name: 'Kathmandu') }

  describe 'GET /admin/manage-address' do
    it 'lists provinces with their districts' do
      get '/admin/manage-address'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Bagmati')
      expect(response.body).to include('Kathmandu')
      expect(response.body).to include('Kaski')
    end
  end

  describe 'GET /admin/orders/:id — Shipping Address block' do
    let(:nepal_country) do
      Spree::Country.find_by(iso: 'NP') ||
        create(:country, iso: 'NP', iso3: 'NPL', name: 'Nepal', states_required: false)
    end

    let(:nepal_address) do
      create(
        :address,
        country: nepal_country, state: nil, province: bagmati, district: kathmandu,
        address1: 'Ward 4, Pako', city: 'Thamel', zipcode: nil, phone: '9841234567',
        alternative_phone: nil
      )
    end

    let(:order) do
      create(:shipped_order, ship_address: nepal_address, bill_address: nepal_address)
    end

    it 'shows the full Nepal address format (district + province)' do
      get "/admin/orders/#{order.to_param}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('class="nepal-address"')
      expect(response.body).to include('<dd class="district">Kathmandu</dd>')
      expect(response.body).to include('<dd class="province">Bagmati</dd>')
      expect(response.body).to include('<dd class="locality">Thamel</dd>')
      expect(response.body).to include('Ward 4, Pako')
    end

    it 'labels every line of the format' do
      get "/admin/orders/#{order.to_param}"

      expect(response.body).to include('City or municipality')
      expect(response.body).to include('District')
      expect(response.body).to include('Province')
    end

    it 'keeps the stock markup for non-Nepal addresses' do
      order.ship_address.update_columns(city: 'New York', province_id: nil, district_id: nil)

      get "/admin/orders/#{order.to_param}"

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('class="nepal-address"')
      expect(response.body).to include('class="local"')
    end
  end

  describe 'PATCH /admin/provinces/:id' do
    it 'renames the display name' do
      patch "/admin/provinces/#{bagmati.to_param}", params: { province: { name: 'Bagmati Pradesh' } }

      expect(response).to have_http_status(:redirect)
      expect(bagmati.reload.name).to eq('Bagmati Pradesh')
    end
  end

  describe 'POST /admin/districts' do
    it 'adds a district to a province' do
      expect do
        post '/admin/districts', params: { district: { name: 'New District', province_id: bagmati.id } }
      end.to change { bagmati.districts.count }.by(1)

      expect(response).to have_http_status(:redirect)
      expect(bagmati.districts.find_by(name: 'New District')).to be_present
    end

    it 'rejects a duplicate name within the province' do
      post '/admin/districts', params: { district: { name: 'Kathmandu', province_id: bagmati.id } }

      expect(response).to have_http_status(:redirect)
      expect(flash[:error]).to be_present
    end
  end

  describe 'PATCH /admin/districts/:id' do
    it 'renames a district' do
      patch "/admin/districts/#{kathmandu.to_param}", params: { district: { name: 'Kathmandu Valley' } }

      expect(kathmandu.reload.name).to eq('Kathmandu Valley')
    end
  end

  describe 'POST /admin/districts/:id/deactivate + activate' do
    it 'deactivates and reactivates' do
      post "/admin/districts/#{kathmandu.to_param}/deactivate"
      expect(kathmandu.reload.active).to be(false)

      post "/admin/districts/#{kathmandu.to_param}/activate"
      expect(kathmandu.reload.active).to be(true)
    end

    it 'hides deactivated districts from the active scope' do
      post "/admin/districts/#{kathmandu.to_param}/deactivate"

      expect(Spree::District.active).not_to include(kathmandu)
    end
  end

  describe 'DELETE /admin/districts/:id' do
    it 'deletes an unreferenced district' do
      disposable = bagmati.districts.create!(name: 'Disposable', shipping_fee: 0)

      expect do
        delete "/admin/districts/#{disposable.to_param}"
      end.to change { Spree::District.count }.by(-1)
    end

    it 'blocks deletion when addresses reference the district' do
      country = Spree::Country.find_by(iso: 'NP') || create(:country, iso: 'NP', iso3: 'NPL', name: 'Nepal')
      create(
        :address, country: country, province: bagmati, district: kathmandu,
                  phone: '9841234567'
      )

      expect do
        delete "/admin/districts/#{kathmandu.to_param}"
      end.not_to(change { Spree::District.count })

      expect(response).to have_http_status(:redirect)
      expect(flash[:error]).to include('Deactivate')
      expect(kathmandu.reload).to be_present
    end
  end
end

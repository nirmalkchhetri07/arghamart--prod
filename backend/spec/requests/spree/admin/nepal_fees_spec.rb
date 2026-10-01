# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Nepal fees', type: :request do
  let(:admin_user) { create(:admin_user) }

  before do
    login_as(admin_user, scope: :admin_user)
    Spree::NepalGeography.seed!
  end

  let(:bagmati) { Spree::Province.find_by!(code: 'BAGMATI') }
  let(:kathmandu) { Spree::District.find_by!(name: 'Kathmandu') }
  let(:lalitpur) { Spree::District.find_by!(name: 'Lalitpur') }

  def calculator
    method = Spree::ShippingMethod.joins(:calculator).
             where(spree_calculators: { type: 'Spree::Calculator::Shipping::DistrictShipping' }).
             first
    if method.nil?
      calc = Spree::Calculator::Shipping::DistrictShipping.create!(
        preferred_default_fee: 0,
        preferred_currency: 'NPR'
      )
      category = Spree::ShippingCategory.find_or_create_by!(name: 'Default')
      method = Spree::ShippingMethod.create!(
        name: 'Nepal Delivery',
        display_on: 'both',
        calculator: calc,
        zones: Spree::Zone.all,
        shipping_categories: [category]
      )
    end
    method.calculator
  end

  describe 'GET /admin/manage-fee' do
    it 'lists every district with province and fee' do
      get '/admin/manage-fee'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Kathmandu')
      expect(response.body).to include('Bagmati')
      expect(response.body).to include('fee not set')
    end

    it 'filters by province' do
      gandaki = Spree::Province.find_by!(code: 'GANDAKI')

      get '/admin/manage-fee', params: { province_id: gandaki.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Kaski')
      expect(response.body).not_to include('Kathmandu')
    end

    it 'searches by district name' do
      get '/admin/manage-fee', params: { q: 'kathm' }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Kathmandu')
      expect(response.body).not_to include('Lalitpur')
    end
  end

  describe 'PATCH /admin/district_fees/:id' do
    it 'updates a single fee' do
      patch "/admin/district_fees/#{kathmandu.to_param}",
            params: { district: { shipping_fee: 150 } }

      expect(response).to have_http_status(:redirect)
      expect(kathmandu.reload.shipping_fee.to_f).to eq(150)
    end

    it 'rejects a negative fee' do
      patch "/admin/district_fees/#{kathmandu.to_param}",
            params: { district: { shipping_fee: -10 } }

      expect(response).to have_http_status(:redirect)
      expect(flash[:error]).to be_present
      expect(kathmandu.reload.shipping_fee.to_f).to eq(0)
    end
  end

  describe 'POST /admin/district_fees/bulk_update' do
    it 'saves many fees in one submit' do
      post '/admin/district_fees/bulk_update',
           params: { fees: { kathmandu.id.to_s => '150', lalitpur.id.to_s => '120' } }

      expect(response).to have_http_status(:redirect)
      expect(kathmandu.reload.shipping_fee.to_f).to eq(150)
      expect(lalitpur.reload.shipping_fee.to_f).to eq(120)
    end
  end

  describe 'POST /admin/district_fees/set_province_fee' do
    it 'sets the fee for the whole province' do
      post '/admin/district_fees/set_province_fee',
           params: { province_id: bagmati.id, shipping_fee: '200' }

      expect(response).to have_http_status(:redirect)
      expect(bagmati.districts.reload.pluck(:shipping_fee).map(&:to_f).uniq).to eq([200])
    end

    it 'rejects a negative province fee' do
      post '/admin/district_fees/set_province_fee',
           params: { province_id: bagmati.id, shipping_fee: '-5' }

      expect(response).to have_http_status(:redirect)
      expect(flash[:error]).to be_present
      expect(kathmandu.reload.shipping_fee.to_f).to eq(0)
    end
  end

  describe 'POST /admin/district_fees/update_default_fee' do
    it 'updates the calculator fallback fee' do
      calc = calculator
      expect(calc).to be_present

      post '/admin/district_fees/update_default_fee', params: { default_fee: '99' }

      expect(response).to have_http_status(:redirect)
      expect(calc.reload.preferred_default_fee.to_f).to eq(99)
    end
  end
end

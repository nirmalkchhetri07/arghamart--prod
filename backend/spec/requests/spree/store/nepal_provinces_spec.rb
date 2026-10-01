# frozen_string_literal: true

require 'rails_helper'
require 'spree/api/testing_support/v3/base'

# Public reference data for the Nepal checkout address form. Guest
# accessible (publishable key only) and HTTP-cached — the storefront loads
# provinces/districts from here, never from a hardcoded list, so districts
# added or deactivated in /admin/manage-address take effect.
RSpec.describe 'Store Nepal provinces', type: :request do
  include_context 'API v3 Store'

  before do
    Spree::NepalGeography.seed!
  end

  describe 'GET /api/v3/store/nepal/provinces' do
    it 'returns all 7 provinces with their active districts' do
      get '/api/v3/store/nepal/provinces', headers: api_key_headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['data'].size).to eq(7)

      bagmati = body['data'].find { |p| p['name'] == 'Bagmati' }
      names = bagmati['districts'].map { |d| d['name'] }
      expect(names).to include('Kathmandu', 'Lalitpur')
    end

    it 'excludes inactive districts' do
      Spree::District.find_by!(name: 'Kathmandu').update!(active: false)

      get '/api/v3/store/nepal/provinces', headers: api_key_headers

      body = JSON.parse(response.body)
      bagmati = body['data'].find { |p| p['name'] == 'Bagmati' }
      names = bagmati['districts'].map { |d| d['name'] }
      expect(names).not_to include('Kathmandu')
      expect(names).to include('Lalitpur')
    end

    it 'is publicly cacheable' do
      get '/api/v3/store/nepal/provinces', headers: api_key_headers

      expect(response.headers['Cache-Control']).to include('public')
    end
  end
end

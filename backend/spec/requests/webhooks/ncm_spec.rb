# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'NCM webhook', type: :request do
  let!(:partner) { create(:delivery_partner) }

  it 'accepts a valid callback secret and JSON payload' do
    post "/webhooks/ncm/#{partner.webhook_secret}",
         params: { event: 'order.status.updated' }.to_json,
         headers: { 'CONTENT_TYPE' => 'application/json' }

    expect(response).to have_http_status(:ok)
  end

  it 'rejects an invalid callback secret' do
    post '/webhooks/ncm/invalid',
         params: { event: 'order.status.updated' }.to_json,
         headers: { 'CONTENT_TYPE' => 'application/json' }

    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects malformed JSON' do
    post "/webhooks/ncm/#{partner.webhook_secret}",
         params: '{not-json',
          headers: { 'CONTENT_TYPE' => 'text/plain' }

    expect(response).to have_http_status(:bad_request)
  end
end
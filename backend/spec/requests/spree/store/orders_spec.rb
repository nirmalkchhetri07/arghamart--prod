# frozen_string_literal: true

require 'rails_helper'
require 'spree/api/testing_support/v3/base'

# The Store API order payload embeds fulfillments — staff mark delivery in
# the admin and the storefront reads it back here for the customer's order
# history page.
RSpec.describe 'Store API order delivery status', type: :request do
  include_context 'API v3 Store'

  let(:order) { create(:shipped_order, store: store) }

  def order_headers(order)
    {
      'X-Spree-Api-Key' => api_key.token,
      'X-Spree-Token' => order.token,
      'Content-Type' => 'application/json'
    }
  end

  def fulfillments_for(order)
    get "/api/v3/store/orders/#{order.prefixed_id}", headers: order_headers(order)
    expect(response).to have_http_status(:ok)
    json_response['fulfillments']
  end

  it 'exposes delivered_at (nil) and delivered (false) before delivery' do
    fulfillments = fulfillments_for(order)

    expect(fulfillments.size).to eq(order.shipments.count)
    expect(fulfillments.first['delivered_at']).to be_nil
    expect(fulfillments.first['delivered']).to be(false)
  end

  it 'reflects the delivery once the shipment is marked as delivered' do
    order.shipments.first.mark_as_delivered!

    fulfillments = fulfillments_for(order)

    expect(fulfillments.first['delivered_at']).to be_present
    expect(fulfillments.first['delivered']).to be(true)
  end
end

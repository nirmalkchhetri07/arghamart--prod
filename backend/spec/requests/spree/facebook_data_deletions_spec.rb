# frozen_string_literal: true

require 'rails_helper'
require 'spree/api/testing_support/v3/base'

RSpec.describe 'Store API Facebook data deletion', type: :request do
  include_context 'API v3 Store'

  let(:headers) do
    { 'X-Spree-Api-Key' => api_key.token, 'Content-Type' => 'application/json' }
  end

  before { Rails.cache.clear }

  let!(:provider_record) do
    create(:oauth_provider, provider: 'facebook', name: 'Facebook',
                            client_id: 'fb-app-id', client_secret: 'fb-secret', enabled: true)
  end

  def signed_request(user_id:, secret: 'fb-secret', algorithm: 'HMAC-SHA256')
    payload = Base64.urlsafe_encode64(
      { algorithm: algorithm, issued_at: Time.now.to_i, user_id: user_id }.to_json, padding: false
    )
    sig = Base64.urlsafe_encode64(OpenSSL::HMAC.digest('SHA256', secret, payload), padding: false)
    "#{sig}.#{payload}"
  end

  def post_deletion(signed_request_value)
    post '/api/v3/store/facebook/data_deletion',
         params: { signed_request: signed_request_value }.to_json, headers: headers
  end

  it 'removes the matching identities and returns url + confirmation code' do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('STOREFRONT_URL').and_return('https://arghamart-prod.vercel.app')
    owner = create(:user, email: 'ada@example.com')
    other = create(:user, email: 'other@example.com')
    create(:oauth_identity, user: owner, provider: 'facebook', uid: 'fb-123')
    create(:oauth_identity, user: other, provider: 'google', uid: 'google-sub-9')

    post_deletion(signed_request(user_id: 'fb-123'))

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['confirmation_code']).to be_present
    expect(body['url']).to eq(
      "https://arghamart-prod.vercel.app/data-deletion-status?code=#{body['confirmation_code']}"
    )
    expect(Spree::OauthIdentity.find_by(provider: 'facebook', uid: 'fb-123')).to be_nil
    # The store accounts themselves are untouched.
    expect(owner.reload).to be_present
    expect(Spree::OauthIdentity.find_by(provider: 'google', uid: 'google-sub-9')).to be_present
  end

  it 'rejects a forged signature' do
    post_deletion(signed_request(user_id: 'fb-123', secret: 'attacker-secret'))

    expect(response).to have_http_status(:bad_request)
    expect(JSON.parse(response.body)['error']['code']).to eq('invalid_token')
  end

  it 'rejects a malformed signed_request' do
    post_deletion('garbage-without-separator')

    expect(response).to have_http_status(:bad_request)
  end

  it 'refuses when no Facebook provider is configured' do
    provider_record.destroy!

    post_deletion(signed_request(user_id: 'fb-123'))

    expect(response).to have_http_status(:bad_request)
    expect(JSON.parse(response.body)['error']['code']).to eq('provider_disabled')
  end
end

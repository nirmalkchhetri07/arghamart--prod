# frozen_string_literal: true

require 'rails_helper'
require 'spree/api/testing_support/v3/base'

RSpec.describe 'Store API OAuth', type: :request do
  include_context 'API v3 Store'

  let(:headers) do
    { 'X-Spree-Api-Key' => api_key.token, 'Content-Type' => 'application/json' }
  end

  before { Rails.cache.clear }

  describe 'GET /api/v3/store/oauth_providers' do
    it 'returns only enabled, implemented providers without secrets' do
      create(:oauth_provider, provider: 'google', name: 'Google', client_id: 'google-id', enabled: true)
      create(:oauth_provider, provider: 'facebook', name: 'Facebook', client_id: 'fb-id', enabled: true)
      create(:oauth_provider, provider: 'github', name: 'GitHub', client_id: 'gh-id', enabled: true)
      # Unimplemented rows cannot be created through validation; force one
      # to prove the endpoint filters them anyway.
      build(:oauth_provider, provider: 'myspace', name: 'Myspace', client_id: 'my-id', enabled: true).
        save!(validate: false)

      get '/api/v3/store/oauth_providers', headers: headers

      expect(response).to have_http_status(:ok)
      providers = JSON.parse(response.body)['data']
      expect(providers).to eq(
        [
          { 'provider' => 'facebook', 'name' => 'Facebook', 'client_id' => 'fb-id' },
          { 'provider' => 'github', 'name' => 'GitHub', 'client_id' => 'gh-id' },
          { 'provider' => 'google', 'name' => 'Google', 'client_id' => 'google-id' }
        ]
      )
      expect(response.body).not_to include('secret')
    end

    it 'excludes disabled providers' do
      create(:oauth_provider, provider: 'google', enabled: false)

      get '/api/v3/store/oauth_providers', headers: headers

      expect(JSON.parse(response.body)['data']).to eq([])
    end
  end

  describe 'POST /api/v3/store/auth/:provider' do
    let!(:provider_record) { create(:oauth_provider, provider: 'google', enabled: true) }

    def stub_verification(result)
      allow(Spree::Oauth::GoogleVerifier).to receive(:verify).and_return(result)
    end

    let(:verified_payload) do
      { uid: 'google-sub-1', email: 'ginny@example.com', email_verified: true,
        first_name: 'Ginny', last_name: 'Weasley' }
    end

    def login(credential = 'id-token-jwt')
      post '/api/v3/store/auth/google', params: { credential: credential }.to_json, headers: headers
    end

    it 'creates a new user on first login and returns stock-shaped tokens' do
      stub_verification(verified_payload)

      expect { login }.to change { Spree.user_class.count }.by(1)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['token']).to be_present
      expect(body['refresh_token']).to be_present
      expect(body['user']['email']).to eq('ginny@example.com')
      expect(Spree::OauthIdentity.find_by(provider: 'google', uid: 'google-sub-1')).to be_present
    end

    it 'links an identity to the existing account for a known email' do
      owner = create(:user, email: 'ginny@example.com')
      stub_verification(verified_payload)

      expect { login }.not_to(change { Spree.user_class.count })

      body = JSON.parse(response.body)
      expect(body['user']['email']).to eq('ginny@example.com')
      identity = Spree::OauthIdentity.find_by!(provider: 'google', uid: 'google-sub-1')
      expect(identity.user).to eq(owner)
    end

    it 'reuses an existing identity without duplicates' do
      owner = create(:user, email: 'ginny@example.com')
      create(:oauth_identity, user: owner, provider: 'google', uid: 'google-sub-1')
      stub_verification(verified_payload)

      expect { login }.not_to(change { Spree::OauthIdentity.count })

      expect(JSON.parse(response.body)['user']['email']).to eq('ginny@example.com')
    end

    it 'rejects unverified emails' do
      stub_verification(verified_payload.merge(email_verified: false))

      login

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)['error']['code']).to eq('email_not_verified')
    end

    it 'rejects disabled providers' do
      provider_record.update!(enabled: false)
      stub_verification(verified_payload)

      login

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)['error']['code']).to eq('provider_disabled')
    end

    it 'rejects invalid tokens' do
      allow(Spree::Oauth::GoogleVerifier).to receive(:verify).
        and_raise(Spree::Oauth::InvalidToken, 'bad signature')

      login

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)['error']['code']).to eq('invalid_token')
    end

    it 'rejects unknown providers' do
      post '/api/v3/store/auth/myspace', params: { credential: 'x' }.to_json, headers: headers

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe 'POST /api/v3/store/auth/facebook' do
    let!(:provider_record) do
      create(:oauth_provider, provider: 'facebook', name: 'Facebook',
                              client_id: 'fb-id', client_secret: 'fb-secret', enabled: true)
    end
    let(:redirect_uri) { 'https://store.example.com/us/en/auth/callback/facebook' }
    let(:verified_payload) do
      { uid: 'fb-123', email: 'ada@example.com', email_verified: true,
        first_name: 'Ada', last_name: 'Lovelace' }
    end

    def facebook_login(params = {})
      post '/api/v3/store/auth/facebook',
           params: { credential: 'auth-code-1', redirect_uri: redirect_uri }.merge(params).to_json,
           headers: headers
    end

    it 'passes the code and redirect_uri to the verifier and creates the user' do
      expect(Spree::Oauth::FacebookVerifier).to receive(:verify).
        with('auth-code-1', an_object_having_attributes(provider: 'facebook'), redirect_uri: redirect_uri).
        and_return(verified_payload)

      expect { facebook_login }.to change { Spree.user_class.count }.by(1)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['user']['email']).to eq('ada@example.com')
      expect(Spree::OauthIdentity.find_by(provider: 'facebook', uid: 'fb-123')).to be_present
    end

    it 'rejects a missing redirect_uri' do
      facebook_login(redirect_uri: nil)

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)['error']['code']).to eq('invalid_token')
    end

    it 'rejects unverified emails' do
      allow(Spree::Oauth::FacebookVerifier).to receive(:verify).
        and_raise(Spree::Oauth::EmailNotVerified, 'Email address is not verified')

      facebook_login

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)['error']['code']).to eq('email_not_verified')
    end
  end

  describe 'POST /api/v3/store/auth/github' do
    let!(:provider_record) do
      create(:oauth_provider, provider: 'github', name: 'GitHub',
                              client_id: 'gh-id', client_secret: 'gh-secret', enabled: true)
    end
    let(:redirect_uri) { 'https://store.example.com/us/en/auth/callback/github' }
    let(:verified_payload) do
      { uid: '42424242', email: 'tux@example.com', email_verified: true,
        first_name: 'Tux', last_name: nil }
    end

    def github_login(params = {})
      post '/api/v3/store/auth/github',
           params: { credential: 'auth-code-1', redirect_uri: redirect_uri }.merge(params).to_json,
           headers: headers
    end

    it 'passes the code and redirect_uri to the verifier and creates the user' do
      expect(Spree::Oauth::GithubVerifier).to receive(:verify).
        with('auth-code-1', an_object_having_attributes(provider: 'github'), redirect_uri: redirect_uri).
        and_return(verified_payload)

      expect { github_login }.to change { Spree.user_class.count }.by(1)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['user']['email']).to eq('tux@example.com')
      expect(Spree::OauthIdentity.find_by(provider: 'github', uid: '42424242')).to be_present
    end

    it 'rejects a missing redirect_uri' do
      github_login(redirect_uri: nil)

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)['error']['code']).to eq('invalid_token')
    end
  end
end

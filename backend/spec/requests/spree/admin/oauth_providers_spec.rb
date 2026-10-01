# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Social Login providers', type: :request do
  let(:admin_user) { create(:admin_user) }

  before { login_as(admin_user, scope: :admin_user) }

  def provider_params(overrides = {})
    {
      provider: 'google',
      name: 'Google',
      client_id: 'test.apps.googleusercontent.com',
      client_secret: 'shh-secret',
      enabled: true,
      position: 0
    }.merge(overrides)
  end

  describe 'GET /admin/social-login' do
    it 'lists providers with masked client_id' do
      create(:oauth_provider)

      get '/admin/social-login'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Google')
      expect(response.body).not_to include('shh-secret')
    end
  end

  describe 'GET new/edit' do
    it 'renders the provider form' do
      record = create(:oauth_provider)

      get '/admin/oauth_providers/new'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Google')

      get "/admin/oauth_providers/#{record.id}/edit"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Leave blank to keep the stored secret')
    end
  end

  describe 'POST /admin/oauth_providers' do
    it 'creates an enabled Google provider' do
      expect { post '/admin/oauth_providers', params: { oauth_provider: provider_params } }.
        to change { Spree::OauthProvider.count }.by(1)

      record = Spree::OauthProvider.find_by!(provider: 'google')
      expect(record).to be_enabled
      expect(record.client_secret).to eq('shh-secret')
      expect(response).to redirect_to('/admin/social-login')
    end

    it 'rejects unknown providers' do
      expect { post '/admin/oauth_providers', params: { oauth_provider: provider_params(provider: 'myspace') } }.
        not_to(change { Spree::OauthProvider.count })

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'creates Facebook and GitHub code-exchange providers' do
      expect do
        post '/admin/oauth_providers', params: { oauth_provider: provider_params(provider: 'facebook', name: 'Facebook', client_id: 'fb-id') }
      end.
        to change { Spree::OauthProvider.count }.by(1)

      expect { post '/admin/oauth_providers', params: { oauth_provider: provider_params(provider: 'github', name: 'GitHub', client_id: 'gh-id') } }.
        to change { Spree::OauthProvider.count }.by(1)

      expect(response).to redirect_to('/admin/social-login')
    end
  end

  describe 'PATCH /admin/oauth_providers/:id' do
    it 'updates the name and keeps the stored secret when blank' do
      record = create(:oauth_provider, client_secret: 'original-secret')

      patch "/admin/oauth_providers/#{record.id}", params: { oauth_provider: { name: 'Google Login' } }

      expect(response).to redirect_to('/admin/social-login')
      expect(record.reload.name).to eq('Google Login')
      expect(record.client_secret).to eq('original-secret')
    end

    it 'replaces the secret when a new one is typed' do
      record = create(:oauth_provider, client_secret: 'original-secret')

      patch "/admin/oauth_providers/#{record.id}",
            params: { oauth_provider: { client_secret: 'rotated-secret' } }

      expect(record.reload.client_secret).to eq('rotated-secret')
    end
  end

  describe 'POST /admin/oauth_providers/:id/toggle' do
    it 'flips enabled on and off' do
      record = create(:oauth_provider, enabled: true)

      post "/admin/oauth_providers/#{record.id}/toggle"
      expect(record.reload).not_to be_enabled

      post "/admin/oauth_providers/#{record.id}/toggle"
      expect(record.reload).to be_enabled
    end
  end

  describe 'DELETE /admin/oauth_providers/:id' do
    it 'removes the provider but keeps users and identities' do
      record = create(:oauth_provider)
      user = create(:user, email: 'social@example.com')
      identity = create(:oauth_identity, user: user, provider: 'google', uid: 'sub-1')

      expect { delete "/admin/oauth_providers/#{record.id}" }.
        to change { Spree::OauthProvider.count }.by(-1)

      expect(response).to redirect_to('/admin/social-login')
      expect(user.reload).to be_present
      expect(identity.reload).to be_present
    end
  end

  describe 'permissions' do
    it 'redirects non-admin users away' do
      logout(:admin_user)
      login_as(create(:user, email: 'plain@example.com'), scope: :user)

      get '/admin/social-login'

      expect(response).not_to have_http_status(:ok)
    end
  end
end

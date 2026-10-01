# frozen_string_literal: true

require 'rails_helper'
require 'webmock/rspec'

# Covers the Facebook authorization-code flow:
#  - code exchange with the provider record's client_secret
#  - profile fetch returning a verified email identity
#  - rejections for missing code/secret/redirect_uri, provider errors, and
#    missing email permission
#
# Outbound HTTP to graph.facebook.com is stubbed with WebMock (inline
# stubs, no live calls, no secrets in the repo).
RSpec.describe Spree::Oauth::FacebookVerifier do
  let(:redirect_uri) { 'https://store.example.com/us/en/auth/callback/facebook' }
  let(:provider_record) do
    build(:oauth_provider, provider: 'facebook', name: 'Facebook',
                           client_id: 'fb-app-id', client_secret: 'fb-secret')
  end
  let(:exchange_url) { 'https://graph.facebook.com/v20.0/oauth/access_token' }
  let(:profile_url) { 'https://graph.facebook.com/v20.0/me' }

  def stub_exchange(code: 'auth-code-1', token: 'fb-access-token', status: 200, body: nil)
    stub_request(:get, exchange_url).
      with(query: hash_including(
        'client_id' => 'fb-app-id',
        'client_secret' => 'fb-secret',
        'redirect_uri' => redirect_uri,
        'code' => code
      )).
      to_return(status: status,
                body: (body || { 'access_token' => token, 'token_type' => 'bearer' }).to_json,
                headers: { 'Content-Type' => 'application/json' })
  end

  def stub_profile(token: 'fb-access-token', status: 200, body: nil)
    stub_request(:get, profile_url).
      with(query: hash_including('access_token' => token)).
      to_return(status: status,
                body: (body || { 'id' => 'fb-123', 'first_name' => 'Ada',
                                 'last_name' => 'Lovelace', 'email' => 'ada@example.com' }).to_json,
                headers: { 'Content-Type' => 'application/json' })
  end

  it 'returns the verified identity for a valid code' do
    stub_exchange
    stub_profile

    result = described_class.verify('auth-code-1', provider_record, redirect_uri: redirect_uri)

    expect(result).to eq(uid: 'fb-123', email: 'ada@example.com', email_verified: true,
                         first_name: 'Ada', last_name: 'Lovelace')
  end

  it 'rejects a blank code' do
    expect { described_class.verify('', provider_record, redirect_uri: redirect_uri) }.
      to raise_error(Spree::Oauth::InvalidToken, /Authorization code is required/)
  end

  it 'rejects a missing client secret' do
    provider_record.client_secret = nil

    expect { described_class.verify('auth-code-1', provider_record, redirect_uri: redirect_uri) }.
      to raise_error(Spree::Oauth::InvalidToken, /client secret/)
  end

  it 'rejects a missing redirect_uri' do
    expect { described_class.verify('auth-code-1', provider_record) }.
      to raise_error(Spree::Oauth::InvalidToken, /redirect_uri/)
  end

  it 'rejects a failed code exchange' do
    stub_exchange(code: 'bad-code',
                  body: { 'error' => { 'message' => 'Invalid verification code format.' } })

    expect { described_class.verify('bad-code', provider_record, redirect_uri: redirect_uri) }.
      to raise_error(Spree::Oauth::InvalidToken, /code exchange failed/)
  end

  it 'rejects a profile fetch error' do
    stub_exchange
    stub_profile(status: 400, body: { 'error' => { 'message' => 'Invalid OAuth access token.' } })

    expect { described_class.verify('auth-code-1', provider_record, redirect_uri: redirect_uri) }.
      to raise_error(Spree::Oauth::InvalidToken, /profile fetch failed/)
  end

  it 'rejects a profile without an email (permission denied)' do
    stub_exchange
    stub_profile(body: { 'id' => 'fb-123', 'first_name' => 'Ada' })

    expect { described_class.verify('auth-code-1', provider_record, redirect_uri: redirect_uri) }.
      to raise_error(Spree::Oauth::InvalidToken, /email is missing/)
  end
end

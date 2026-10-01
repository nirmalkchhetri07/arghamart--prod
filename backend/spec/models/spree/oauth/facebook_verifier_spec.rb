# frozen_string_literal: true

require 'rails_helper'
require 'webmock/rspec'

# Covers the Facebook user-access-token flow:
#  - debug_token inspection (validity, app binding, expiry)
#  - profile fetch with appsecret_proof, returning an unverified identity
#  - rejections for bad/foreign/expired tokens, missing secret, and
#    provider errors
#
# Outbound HTTP to graph.facebook.com is stubbed with WebMock (inline
# stubs, no live calls, no secrets in the repo).
RSpec.describe Spree::Oauth::FacebookVerifier do
  let(:provider_record) do
    build(:oauth_provider, provider: 'facebook', name: 'Facebook',
                           client_id: 'fb-app-id', client_secret: 'fb-secret')
  end
  let(:token) { 'user-access-token-1' }
  let(:debug_url) { 'https://graph.facebook.com/v20.0/debug_token' }
  let(:profile_url) { 'https://graph.facebook.com/v20.0/me' }
  let(:proof) { OpenSSL::HMAC.hexdigest('SHA256', 'fb-secret', token) }

  def stub_debug(body: nil, status: 200)
    stub_request(:get, debug_url).
      with(query: hash_including(
        'input_token' => token,
        'access_token' => 'fb-app-id|fb-secret'
      )).
      to_return(status: status,
                body: (body || { 'data' => {
                  'app_id' => 'fb-app-id', 'is_valid' => true,
                  'user_id' => 'fb-123', 'expires_at' => (Time.now + 1.hour).to_i
                } }).to_json,
                headers: { 'Content-Type' => 'application/json' })
  end

  def stub_profile(body: nil, status: 200)
    stub_request(:get, profile_url).
      with(query: hash_including('access_token' => token, 'appsecret_proof' => proof)).
      to_return(status: status,
                body: (body || { 'id' => 'fb-123', 'first_name' => 'Ada',
                                 'last_name' => 'Lovelace', 'email' => 'ada@example.com' }).to_json,
                headers: { 'Content-Type' => 'application/json' })
  end

  it 'returns the identity with email_verified false for a valid token' do
    stub_debug
    stub_profile

    result = described_class.verify(token, provider_record)

    expect(result).to eq(uid: 'fb-123', email: 'ada@example.com', email_verified: false,
                         first_name: 'Ada', last_name: 'Lovelace')
  end

  it 'returns a nil email when Facebook shares none' do
    stub_debug
    stub_profile(body: { 'id' => 'fb-123', 'first_name' => 'Ada' })

    result = described_class.verify(token, provider_record)

    expect(result[:email]).to be_nil
    expect(result[:email_verified]).to be(false)
  end

  it 'rejects a blank token' do
    expect { described_class.verify('', provider_record) }.
      to raise_error(Spree::Oauth::InvalidToken, /Access token is required/)
  end

  it 'rejects a missing client secret' do
    provider_record.client_secret = nil

    expect { described_class.verify(token, provider_record) }.
      to raise_error(Spree::Oauth::InvalidToken, /client secret/)
  end

  it 'rejects an invalid token' do
    stub_debug(body: { 'data' => { 'app_id' => 'fb-app-id', 'is_valid' => false } })

    expect { described_class.verify(token, provider_record) }.
      to raise_error(Spree::Oauth::InvalidToken, /not valid/)
  end

  it 'rejects a token issued for a different app' do
    stub_debug(body: { 'data' => {
                 'app_id' => 'attacker-app-id', 'is_valid' => true,
                 'user_id' => 'fb-123', 'expires_at' => (Time.now + 1.hour).to_i
               } })

    expect { described_class.verify(token, provider_record) }.
      to raise_error(Spree::Oauth::InvalidToken, /different app/)
  end

  it 'rejects an expired token' do
    stub_debug(body: { 'data' => {
                 'app_id' => 'fb-app-id', 'is_valid' => true,
                 'user_id' => 'fb-123', 'expires_at' => (Time.now - 1.hour).to_i
               } })

    expect { described_class.verify(token, provider_record) }.
      to raise_error(Spree::Oauth::InvalidToken, /expired/)
  end

  it 'rejects a debug_token provider error' do
    stub_debug(body: { 'error' => { 'message' => 'Invalid OAuth access token.' } })

    expect { described_class.verify(token, provider_record) }.
      to raise_error(Spree::Oauth::InvalidToken, /inspection failed/)
  end

  it 'rejects a profile fetch error' do
    stub_debug
    stub_profile(status: 400, body: { 'error' => { 'message' => 'Invalid OAuth access token.' } })

    expect { described_class.verify(token, provider_record) }.
      to raise_error(Spree::Oauth::InvalidToken, /profile fetch failed/)
  end

  it 'maps network failures to invalid_token' do
    stub_request(:get, %r{graph\.facebook\.com/v20\.0/debug_token}).to_timeout

    expect { described_class.verify(token, provider_record) }.
      to raise_error(Spree::Oauth::InvalidToken, /verification failed/)
  end
end

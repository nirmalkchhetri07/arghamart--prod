# frozen_string_literal: true

require 'rails_helper'
require 'webmock/rspec'

# Covers the GitHub authorization-code flow:
#  - code exchange with the provider record's client_secret
#  - profile + verified-primary-email resolution
#  - rejections for missing code/secret/redirect_uri, provider errors,
#    missing email, and unverified-only emails
#
# Outbound HTTP to github.com / api.github.com is stubbed with WebMock
# (inline stubs, no live calls, no secrets in the repo).
RSpec.describe Spree::Oauth::GithubVerifier do
  let(:redirect_uri) { 'https://store.example.com/us/en/auth/callback/github' }
  let(:provider_record) do
    build(:oauth_provider, provider: 'github', name: 'GitHub',
                           client_id: 'gh-client-id', client_secret: 'gh-secret')
  end
  let(:exchange_url) { 'https://github.com/login/oauth/access_token' }
  let(:user_url) { 'https://api.github.com/user' }
  let(:emails_url) { 'https://api.github.com/user/emails' }

  def stub_exchange(code: 'auth-code-1', token: 'gh-access-token', status: 200, body: nil)
    stub_request(:post, exchange_url).
      with(body: hash_including('client_id' => 'gh-client-id', 'code' => code, 'redirect_uri' => redirect_uri)).
      to_return(status: status,
                body: (body || { 'access_token' => token, 'scope' => 'user:email', 'token_type' => 'bearer' }).to_json,
                headers: { 'Content-Type' => 'application/json' })
  end

  def stub_user(token: 'gh-access-token', body: nil)
    stub_request(:get, user_url).
      with(headers: { 'Authorization' => "Bearer #{token}" }).
      to_return(status: 200,
                body: (body || { 'id' => 42_424_242, 'login' => 'octocat', 'name' => 'Ada Lovelace',
                                 'email' => nil }).to_json,
                headers: { 'Content-Type' => 'application/json' })
  end

  def stub_emails(token: 'gh-access-token', body: nil)
    stub_request(:get, emails_url).
      with(headers: { 'Authorization' => "Bearer #{token}" }).
      to_return(status: 200,
                body: (body || [
                  { 'email' => 'unverified@example.com', 'primary' => false, 'verified' => false },
                  { 'email' => 'ada@example.com', 'primary' => true, 'verified' => true }
                ]).to_json,
                headers: { 'Content-Type' => 'application/json' })
  end

  it 'returns the verified identity, preferring the primary verified email' do
    stub_exchange
    stub_user
    stub_emails

    result = described_class.verify('auth-code-1', provider_record, redirect_uri: redirect_uri)

    expect(result).to eq(uid: '42424242', email: 'ada@example.com', email_verified: true,
                         first_name: 'Ada', last_name: 'Lovelace')
  end

  it 'falls back to any verified email when no primary is verified' do
    stub_exchange
    stub_user
    stub_emails(body: [
                  { 'email' => 'primary@example.com', 'primary' => true, 'verified' => false },
                  { 'email' => 'secondary@example.com', 'primary' => false, 'verified' => true }
                ])

    result = described_class.verify('auth-code-1', provider_record, redirect_uri: redirect_uri)

    expect(result[:email]).to eq('secondary@example.com')
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
                  body: { 'error' => 'incorrect_client_credentials',
                          'error_description' => 'The client_id and/or client_secret passed are incorrect.' })

    expect { described_class.verify('bad-code', provider_record, redirect_uri: redirect_uri) }.
      to raise_error(Spree::Oauth::InvalidToken, /code exchange failed/)
  end

  it 'rejects when no email address exists at all' do
    stub_exchange
    stub_user
    stub_emails(body: [])

    expect { described_class.verify('auth-code-1', provider_record, redirect_uri: redirect_uri) }.
      to raise_error(Spree::Oauth::InvalidToken, /email is missing/)
  end

  it 'rejects unverified-only emails' do
    stub_exchange
    stub_user
    stub_emails(body: [{ 'email' => 'shady@example.com', 'primary' => true, 'verified' => false }])

    expect { described_class.verify('auth-code-1', provider_record, redirect_uri: redirect_uri) }.
      to raise_error(Spree::Oauth::EmailNotVerified)
  end
end

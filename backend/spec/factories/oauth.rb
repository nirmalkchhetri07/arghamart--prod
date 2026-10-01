# frozen_string_literal: true

FactoryBot.define do
  factory :oauth_provider, class: 'Spree::OauthProvider' do
    provider { 'google' }
    name { 'Google' }
    client_id { 'test.apps.googleusercontent.com' }
    client_secret { 'test-secret' }
    enabled { true }
    position { 0 }
  end

  factory :oauth_identity, class: 'Spree::OauthIdentity' do
    association :user
    provider { 'google' }
    sequence(:uid) { |n| "google-sub-#{n}" }
    email { 'social-customer@example.com' }
  end
end

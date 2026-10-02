# frozen_string_literal: true

FactoryBot.define do
  factory :delivery_partner, class: 'Spree::DeliveryPartner' do
    provider { 'ncm' }
    environment { 'sandbox' }
    webhook_secret { SecureRandom.hex(32) }
    active { false }
  end
end
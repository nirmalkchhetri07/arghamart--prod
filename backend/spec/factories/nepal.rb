# frozen_string_literal: true

FactoryBot.define do
  factory :nepali_province, class: 'Spree::Province' do
    sequence(:name) { |n| "Test Province #{n}" }
    sequence(:code) { |n| "TEST#{n}" }
    position { 99 }
  end

  factory :nepali_district, class: 'Spree::District' do
    association :province, factory: :nepali_province
    sequence(:name) { |n| "Test District #{n}" }
    shipping_fee { 100 }
    active { true }
  end
end

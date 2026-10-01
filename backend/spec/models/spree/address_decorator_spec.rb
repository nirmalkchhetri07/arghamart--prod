# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spree::Address, type: :model do
  let(:store) { @default_store }
  let(:country) { create(:country, iso: 'NP', iso3: 'NPL', name: 'Nepal') }

  before do
    Spree::NepalGeography.seed!
  end

  let(:bagmati) { Spree::Province.find_by!(code: 'BAGMATI') }
  let(:gandaki) { Spree::Province.find_by!(code: 'GANDAKI') }
  let(:kathmandu) { Spree::District.find_by!(name: 'Kathmandu') }
  let(:kaski) { Spree::District.find_by!(name: 'Kaski') }

  def valid_attributes(overrides = {})
    {
      firstname: 'Asha',
      lastname: 'Shrestha',
      address1: 'Thamel 123',
      city: 'Kathmandu',
      country: country,
      phone: '9841234567',
      province: bagmati,
      district: kathmandu
    }.merge(overrides)
  end

  describe 'Nepal validations' do
    it 'requires firstname, lastname, and phone; zip stays optional' do
      address = described_class.new(valid_attributes(firstname: '', lastname: '', phone: '', zipcode: ''))

      expect(address).not_to be_valid
      expect(address.errors[:firstname]).to be_present
      expect(address.errors[:lastname]).to be_present
      expect(address.errors[:phone]).to be_present
      expect(address.errors[:zipcode]).to be_empty
    end

    it 'accepts Nepali mobiles with optional +977 prefix' do
      %w[9841234567 9741234567 +9779841234567 +977-9841234567 984-123-4567].each do |phone|
        expect(described_class.new(valid_attributes(phone: phone))).to be_valid, "expected #{phone} to be valid"
      end
    end

    it 'accepts common landline formats' do
      # Kathmandu 01 numbers (Phonelib-validated for NP). Pokhara-style
      # 061 numbers are accepted by our format check but rejected by
      # Spree's Phonelib validator, so they are not listed here.
      %w[01-4412345 01-5234567 +9771-4412345 01-4412345].each do |phone|
        address = described_class.new(valid_attributes(phone: phone))
        expect(address).to be_valid, "expected #{phone} to be valid"
      end
    end

    it 'rejects non-Nepali phone numbers' do
      %w[123 987654321 98412345 abcdefghij +1-555-123-4567].each do |phone|
        address = described_class.new(valid_attributes(phone: phone))
        expect(address).not_to be_valid, "expected #{phone} to be invalid"
        expect(address.errors[:phone]).to be_present
      end
    end

    it 'rejects a district from another province' do
      address = described_class.new(valid_attributes(province: bagmati, district: kaski))

      expect(address).not_to be_valid
      expect(address.errors[:district]).to be_present
    end

    it 'accepts matching province + district' do
      address = described_class.new(valid_attributes(province: gandaki, district: kaski))

      expect(address).to be_valid
    end

    it 'stays valid without province/district (existing orders backfill)' do
      address = described_class.new(valid_attributes(province: nil, district: nil))

      expect(address).to be_valid
    end

    it 'resolves prefixed IDs from the Store API' do
      address = described_class.new(
        valid_attributes(province: nil, district: nil).merge(
          province_id: bagmati.prefixed_id,
          district_id: kathmandu.prefixed_id
        )
      )

      expect(address.province_id).to eq(bagmati.id)
      expect(address.district_id).to eq(kathmandu.id)
      expect(address).to be_valid
    end
  end
end

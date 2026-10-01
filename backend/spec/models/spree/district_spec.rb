# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spree::District, type: :model do
  let(:province) { Spree::NepalGeography.seed! && Spree::Province.find_by!(code: 'BAGMATI') }

  describe 'validations' do
    it 'requires a name scoped to its province' do
      district = described_class.new(province: province, shipping_fee: 0)

      expect(district).not_to be_valid
    end

    it 'rejects negative shipping fees' do
      district = build(:nepali_district, province: province, shipping_fee: -10)

      expect(district).not_to be_valid
      expect(district.errors[:shipping_fee]).to be_present
    end

    it 'allows the same district name in different provinces' do
      Spree::NepalGeography.seed!
      other = Spree::Province.find_by!(code: 'GANDAKI')
      create(:nepali_district, province: province, name: 'Testville')

      dup_same_province = build(:nepali_district, province: province, name: 'Testville')
      dup_other_province = build(:nepali_district, province: other, name: 'Testville')

      expect(dup_same_province).not_to be_valid
      expect(dup_other_province).to be_valid
    end
  end

  describe 'scopes' do
    it 'hides inactive districts' do
      active = create(:nepali_district, province: province, active: true)
      inactive = create(:nepali_district, province: province, name: 'Hidden Valley', active: false)

      expect(described_class.active).to include(active)
      expect(described_class.active).not_to include(inactive)
    end
  end

  describe '#fee_configured?' do
    it 'is false when the fee is zero' do
      district = build(:nepali_district, shipping_fee: 0)

      expect(district.fee_configured?).to be(false)
    end

    it 'is true when a fee is set' do
      district = build(:nepali_district, shipping_fee: 120)

      expect(district.fee_configured?).to be(true)
    end
  end

  describe '.seed data' do
    it 'seeds 77 districts' do
      Spree::NepalGeography.seed!

      expect(described_class.count).to eq(77)
    end
  end
end

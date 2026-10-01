# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spree::Province, type: :model do
  describe 'validations' do
    it 'requires name and code' do
      province = described_class.new

      expect(province).not_to be_valid
      expect(province.errors[:name]).to be_present
      expect(province.errors[:code]).to be_present
    end

    it 'enforces unique code' do
      create(:nepali_province, code: 'BAGMATI')

      dup = build(:nepali_province, code: 'bagmati')
      expect(dup).not_to be_valid
    end
  end

  describe '.seed data' do
    it 'seeds 7 provinces via NepalGeography' do
      Spree::NepalGeography.seed!

      expect(described_class.count).to eq(7)
      expect(described_class.pluck(:name)).to include('Bagmati', 'Koshi', 'Sudurpashchim')
    end
  end
end

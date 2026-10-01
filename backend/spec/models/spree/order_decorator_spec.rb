# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spree::Order, type: :model do
  let(:store) { @default_store }
  let(:blank_email_user) { create(:user, email: nil, phone: '9841000001') }
  let(:emailed_user) { create(:user, email: 'hasmail@example.com', phone: '9841000002') }

  describe 'blank-email customers (phone-identified)' do
    it 'keeps a typed order email instead of overwriting it with blank' do
      order = Spree::Order.create!(
        store: store, user: blank_email_user, email: 'typed@example.com'
      )

      expect(order.email).to eq('typed@example.com')
    end

    it 'still fills the order email from users that have one' do
      order = Spree::Order.create!(store: store, user: emailed_user)

      expect(order.email).to eq('hasmail@example.com')
    end

    it 'associate_user! preserves a typed order email for blank-email users' do
      order = Spree::Order.create!(store: store, email: 'typed@example.com')

      order.associate_user!(blank_email_user)

      expect(order.reload.user).to eq(blank_email_user)
      expect(order.email).to eq('typed@example.com')
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spree::ShipmentMailer, type: :mailer do
  let(:store) { @default_store || create(:store) }
  let(:order) { create(:shipped_order, store: store) }
  let(:shipment) { order.shipments.first }

  it 'addresses the customer and includes the delivered order number' do
    order.update_column(:email, 'customer@example.com')
    mail = described_class.delivered(shipment.id)

    expect(mail.to).to eq(['customer@example.com'])
    expect(mail.subject).to include(order.number)
    expect(mail.body.encoded).to include(order.number)
    expect(mail.body.encoded).to include('marked as delivered')
  end

  it 'does not generate an email when the order has no customer email' do
    order.update_column(:email, nil)

    mail = described_class.delivered(shipment.id)

    expect(mail.message).to be_a(ActionMailer::Base::NullMail)
  end
end
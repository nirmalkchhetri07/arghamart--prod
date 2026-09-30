# frozen_string_literal: true

require 'rails_helper'

# The admin alert email: subject carries the order number, body carries the
# amount due / claimed and a link to the admin review page.
RSpec.describe Spree::ManualQrMailer, type: :mailer do
  let!(:store_override) do
    store.markets.update_all(currency: 'NPR') if store.respond_to?(:markets)
    # update_column, not update!: the shared store object may already hold
    # 'USD,NPR' in memory from a rolled-back example, and update! would skip
    # the UPDATE — leaving the DB on USD.
    store.update_column(:supported_currencies, 'USD,NPR') if store.has_attribute?(:supported_currencies)
    store.reload
  end

  let(:store) { @default_store || create(:store) }
  let(:payment_method) do
    Spree::PaymentMethod::ManualQr.create!(
      name: 'Fonepay QR',
      active: true,
      display_on: 'front_end',
      store: store,
      preferred_alert_emails: 'ops@example.com'
    )
  end
  let(:order) { create(:completed_order_with_totals, store: store, currency: 'NPR') }
  let(:payment) do
    payment = order.payments.create!(
      payment_method: payment_method,
      amount: order.total,
      response_code: SecureRandom.uuid,
      skip_source_requirement: true
    )
    payment.update!(qr_transaction_id: 'TXN-MAIL-1')
    payment.pend!
    payment
  end

  # Quoted-printable soft line breaks (=\n) can split tokens mid-word.
  def decoded_body(mail)
    mail.body.to_s.gsub("=\n", '')
  end

  it 'is addressed to the given recipients and names the order' do
    mail = described_class.proof_uploaded(payment.id, ['ops@example.com'])

    expect(mail.to).to eq(['ops@example.com'])
    expect(mail.subject).to include(order.number)
    expect(mail.subject).to include(store.name)
  end

  it 'shows the amount due, the claimed amount and the admin review link' do
    mail = described_class.proof_uploaded(payment.id, ['ops@example.com'])
    body = decoded_body(mail)

    expect(body).to include('Amount due')
    expect(body).to include('Payment claimed')
    expect(body).to include(order.number)
    expect(body).to include('TXN-MAIL-1')
    expect(body).to include('/admin/orders/')
    expect(body).to include('Fonepay QR')
  end

  it 'delivers nothing when there is nobody to alert' do
    payment_method.update!(preferred_alert_emails: '')
    mail = described_class.proof_uploaded(payment.id, [])

    expect { mail.deliver_now }.not_to raise_error
    expect(ActionMailer::Base.deliveries).to be_empty
  end
end

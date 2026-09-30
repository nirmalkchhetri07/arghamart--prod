# frozen_string_literal: true

require 'rails_helper'
require 'webmock/rspec'

# "A proof needs review" alert: email to the method's recipients (staff
# fallback when blank) plus the optional JSON / Telegram webhook.
RSpec.describe Spree::ManualQrAlertJob, type: :job do
  # Manual QR is NPR-only: teach the test store NPR (markets + legacy column).
  let!(:store_override) do
    store.markets.update_all(currency: 'NPR') if store.respond_to?(:markets)
    # update_column: the shared store object may already hold 'USD,NPR' in
    # memory from a previous example whose transaction rolled back — update!
    # would then see no change and skip the UPDATE, leaving the DB on USD.
    store.update_column(:supported_currencies, 'USD,NPR') if store.has_attribute?(:supported_currencies)
    store.reload
  end

  let(:store) { @default_store || create(:store) }
  let(:order) { create(:completed_order_with_totals, store: store, currency: 'NPR') }
  let(:payment_method) do
    Spree::PaymentMethod::ManualQr.create!(
      name: 'Manual QR',
      active: true,
      display_on: 'front_end',
      store: store,
      preferred_alert_emails: 'ops@example.com'
    )
  end

  def pending_qr_payment(txn_id: 'TXN-ALERT-1')
    payment = order.payments.create!(
      payment_method: payment_method,
      amount: order.reload.total,
      response_code: SecureRandom.uuid,
      skip_source_requirement: true
    )
    payment.proof_image.attach(
      io: File.open(Rails.root.join('spec/fixtures/files/qr-proof.png')),
      filename: 'qr-proof.png', content_type: 'image/png'
    )
    payment.update!(qr_transaction_id: txn_id)
    payment.pend!
    payment
  end

  def deliveries_to
    ActionMailer::Base.deliveries.flat_map(&:to).flatten
  end

  before { ActionMailer::Base.deliveries.clear }

  describe 'email' do
    it 'notifies the configured alert emails with the order number in the subject' do
      payment = pending_qr_payment

      described_class.perform_now(payment.id)

      expect(deliveries_to).to include('ops@example.com')
      expect(ActionMailer::Base.deliveries.last.subject).to include(order.number)
    end

    it 'falls back to the store staff when no alert emails are configured' do
      payment_method.update!(preferred_alert_emails: '')
      staff = create(:admin_user, email: 'staff@example.com', without_admin_role: true)
      Spree::RoleUser.create!(
        user: staff,
        role: Spree::Role.default_admin_role,
        resource: store,
        store: store
      )
      payment = pending_qr_payment

      described_class.perform_now(payment.id)

      expect(deliveries_to).to include('staff@example.com')
    end

    it 'sends nothing when the payment is no longer pending (already reviewed)' do
      payment = pending_qr_payment
      payment.complete!

      described_class.perform_now(payment.id)

      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  describe 'webhook' do
    it 'posts a JSON payload with text, order and admin link' do
      payment_method.update!(preferred_alert_webhook_url: 'https://hooks.example.com/manual-qr')
      payment = pending_qr_payment

      stub = stub_request(:post, 'https://hooks.example.com/manual-qr').with { |req|
        body = JSON.parse(req.body)
        body['event'] == 'manual_qr.proof_uploaded' &&
          body['order_number'] == order.number &&
          body['transaction_id'] == 'TXN-ALERT-1' &&
          body['text'].present? &&
          body['admin_url'].to_s.include?('/admin/orders/')
      }

      described_class.perform_now(payment.id)

      expect(stub).to have_been_requested
    end

    it 'posts form-encoded text to a Telegram bot URL (chat_id rides in the query)' do
      url = 'https://api.telegram.org/bot123:ABC/sendMessage?chat_id=-100555'
      payment_method.update!(preferred_alert_webhook_url: url)
      payment = pending_qr_payment

      stub = stub_request(:post, url).with { |req|
        req.headers['Content-Type'].to_s.include?('application/x-www-form-urlencoded') &&
          req.body.include?('text=')
      }

      described_class.perform_now(payment.id)

      expect(stub).to have_been_requested
    end

    it 'keeps the email flowing when the webhook is down' do
      payment_method.update!(preferred_alert_webhook_url: 'https://hooks.example.com/manual-qr')
      stub_request(:post, 'https://hooks.example.com/manual-qr').to_return(status: 500)
      payment = pending_qr_payment

      expect { described_class.perform_now(payment.id) }.not_to raise_error

      expect(deliveries_to).to include('ops@example.com')
    end

    it 'ignores a non-http webhook URL without raising' do
      payment_method.update!(preferred_alert_webhook_url: 'file:///etc/passwd')
      payment = pending_qr_payment

      expect { described_class.perform_now(payment.id) }.not_to raise_error

      expect(deliveries_to).to include('ops@example.com')
    end
  end

  it 'skips other payment methods' do
    payment = pending_qr_payment
    payment.update_column(:payment_method_id, nil)

    described_class.perform_now(payment.id)

    expect(ActionMailer::Base.deliveries).to be_empty
  end
end

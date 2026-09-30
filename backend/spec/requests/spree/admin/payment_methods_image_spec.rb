# frozen_string_literal: true

require 'rails_helper'

# Uploading the QR image on Settings > Payments goes through Active Storage —
# Cloudflare R2 in production. When the bucket rejects the write (bad bucket
# name, missing Object Read & Write grant, unreachable endpoint) the admin
# must see the reason in a flash message instead of a generic error page.
RSpec.describe 'Admin Manual QR image upload', type: :request do
  let(:admin_user) { create(:admin_user) }
  let(:store) { @default_store }
  let(:qr_method) do
    Spree::PaymentMethod::ManualQr.create!(
      name: 'Manual QR',
      active: true,
      display_on: 'front_end',
      store: store,
      preferred_instructions: 'Pay to ArghaMart.'
    )
  end
  let(:qr_image) do
    fixture_file_upload(Rails.root.join('spec/fixtures/files/qr-proof.png'), 'image/png')
  end

  before { login_as(admin_user, scope: :admin_user) }

  it 'stores the uploaded QR image' do
    put "/admin/payment_methods/#{qr_method.to_param}",
        params: { payment_method: { qr_image: qr_image } }

    expect(response).to have_http_status(:redirect)
    expect(flash[:error]).to be_nil
    expect(qr_method.reload.qr_image).to be_attached
  end

  it 'shows the storage error when the image cannot be stored' do
    allow_any_instance_of(ActiveStorage::Service::DiskService)
      .to receive(:upload).and_raise(Errno::EACCES)

    put "/admin/payment_methods/#{qr_method.to_param}",
        params: { payment_method: { qr_image: qr_image } }

    expect(response).to have_http_status(:redirect)
    expect(flash[:error]).to include('could not be stored')
    expect(flash[:error]).to include('Permission denied')
    expect(qr_method.reload.qr_image).not_to be_attached
  end
end

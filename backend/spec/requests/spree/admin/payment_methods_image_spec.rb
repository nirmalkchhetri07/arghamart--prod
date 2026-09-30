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

  # The full admin round trip: the direct-upload flow submits a signed blob id
  # (exactly what the Uppy widget's hidden field sends), the save attaches it,
  # and the edit page must render thumbnails that actually resolve — otherwise
  # the image "disappears" on refresh while the database says it's attached.
  it 'renders a working thumbnail after saving a direct-uploaded signed id' do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: File.open(Rails.root.join('spec/fixtures/files/qr-proof.png')),
      filename: 'qr-proof.png', content_type: 'image/png'
    )

    put "/admin/payment_methods/#{qr_method.to_param}",
        params: { payment_method: { qr_image: blob.signed_id } }
    expect(response).to have_http_status(:redirect)

    expect(qr_method.reload.qr_image).to be_attached

    get "/admin/payment_methods/#{qr_method.to_param}/edit"
    expect(response).to have_http_status(:ok)

    doc = Nokogiri::HTML(response.body)
    widget_thumb = doc.at_css('img[data-active-storage-upload-target="thumb"]')
    expect(widget_thumb).to be_present

    # Every Active Storage <img> the page renders must resolve (redirect or
    # 200). Sources may be absolute (the admin renders them with a host) or
    # root-relative — normalize to the path before requesting it.
    as_images = doc.css('img[src]').filter_map do |img|
      src = img['src']
      path = URI.parse(src).path
      path if path.start_with?('/rails/')
    end
    expect(as_images).to include(URI.parse(widget_thumb['src']).path)

    as_images.uniq.each do |path|
      get path
      expect(response).to have_http_status(:redirect).or have_http_status(:ok)
      expect(response.body).not_to include('ActiveStorage::FileNotFoundError')
    end
  end
end

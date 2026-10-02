# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin shipments delivery tracking', type: :request do
  let(:store) { @default_store }
  let(:admin_user) { create(:admin_user) }
  let(:order) { create(:shipped_order, store: store) }
  let(:shipment) { order.shipments.first }

  before { login_as(admin_user, scope: :admin_user) }

  def shipment_path(shipment)
    "/admin/orders/#{shipment.order.to_param}/shipments/#{shipment.to_param}"
  end

  describe 'POST #mark_as_delivered' do
    it 'marks a shipped shipment as delivered' do
      expect do
        post "#{shipment_path(shipment)}/mark_as_delivered"
      end.to have_enqueued_mail(Spree::ShipmentMailer, :delivered).with(shipment.id)

      expect(response).to have_http_status(:redirect)
      expect(flash[:success]).to eq('Shipment successfully marked as delivered')
      expect(shipment.reload.delivered_at).to be_present
    end

    it 'does not change the shipment state' do
      post "#{shipment_path(shipment)}/mark_as_delivered"

      expect(shipment.reload.state).to eq('shipped')
    end

    it 'refuses a shipment that is not shipped' do
      pending_shipment = create(:order_ready_to_ship, store: store).shipments.first

      expect do
        post "#{shipment_path(pending_shipment)}/mark_as_delivered"
      end.not_to have_enqueued_mail(Spree::ShipmentMailer, :delivered)

      expect(response).to have_http_status(:redirect)
      expect(flash[:error]).to eq('Shipment cannot be marked as delivered')
      expect(pending_shipment.reload.delivered_at).to be_nil
    end

    it 'does not enqueue the email again when already delivered' do
      shipment.mark_as_delivered!

      expect do
        post "#{shipment_path(shipment)}/mark_as_delivered"
      end.not_to have_enqueued_mail(Spree::ShipmentMailer, :delivered)
    end
  end

  describe 'admin order page' do
    it 'shows Send to NCM and Ship actions for a ready shipment' do
      ready_order = create(:order_ready_to_ship, store: store)

      get "/admin/orders/#{ready_order.to_param}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Send to NCM')
      expect(response.body).to include('Ship')
    end

    it 'shows Mark as Delivered after the shipment is shipped' do
      ready_shipment = create(:order_ready_to_ship, store: store).shipments.first
      ready_shipment.assign_attributes(tracking: 'TRACK-123')
      ready_shipment.save!

      post "#{shipment_path(ready_shipment)}/ship"

      expect(ready_shipment.reload.state).to eq('shipped')

      get "/admin/orders/#{ready_shipment.order.to_param}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Mark as Delivered')
      expect(response.body).not_to include('Send to NCM')
    end

    it 'shows the Delivered badge once delivered' do
      shipment.mark_as_delivered!

      get "/admin/orders/#{order.to_param}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('badge-delivered')
      expect(response.body).to include('Delivered')
    end

    it 'shows the Delivered badge in both the header and the shipment card' do
      shipment.mark_as_delivered!

      get "/admin/orders/#{order.to_param}"

      expect(response).to have_http_status(:ok)
      expect(response.body.scan('badge-delivered').length).to eq(2)
    end

    it 'shows the Mark as Delivered button while shipped but not delivered' do
      get "/admin/orders/#{order.to_param}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Mark as Delivered')
      expect(response.body).not_to include('badge-delivered')
    end
  end

  describe 'admin orders index' do
    it 'renders with the Delivered filter available' do
      get '/admin/orders'

      expect(response).to have_http_status(:ok)
    end

    it 'shows Delivered instead of Shipped in the shipment state column once delivered' do
      shipment.mark_as_delivered!

      get '/admin/orders'

      expect(response).to have_http_status(:ok)
      start = response.body.index(order.number)
      row = response.body[start, response.body.index('</tr>', start) - start]
      expect(row).to include('badge-delivered')
      expect(row).not_to include('badge-shipped')
    end

    it 'keeps the stock shipment badge for undelivered orders' do
      order # force creation before rendering the index (let is lazy)
      # The factory leaves order.shipment_state stale ('ready' while its
      # shipments are shipped); real shipped orders carry 'shipped'.
      order.update_column(:shipment_state, 'shipped')

      get '/admin/orders'

      expect(response).to have_http_status(:ok)
      start = response.body.index(order.number)
      row = response.body[start, response.body.index('</tr>', start) - start]
      expect(row).to include('badge-shipped')
      expect(row).not_to include('badge-delivered')
    end

    it 'filters shipped-but-not-delivered orders via Ransack' do
      result = Spree::Order.complete.ransack(
        shipments_state_eq: 'shipped',
        shipments_delivered_at_null: true
      ).result.distinct

      expect(result).to include(order)

      order.shipments.first.mark_as_delivered!

      expect(
        Spree::Order.complete.ransack(
          shipments_state_eq: 'shipped',
          shipments_delivered_at_null: true
        ).result.distinct
      ).not_to include(order)
    end
  end

  describe 'admin order URL resolution' do
    # Staff refer to orders by the legacy human-readable number shown in the
    # UI (e.g. R672084530), but Spree 5.6 routes detail pages by prefixed ID
    # (e.g. or_VqXmZF31wY). The number must resolve to the canonical URL
    # instead of bouncing to the index looking "not rendered".
    it 'redirects a legacy order number to the canonical prefixed URL' do
      expect(order.to_param).not_to eq(order.number)

      get "/admin/orders/#{order.number}"

      expect(response).to have_http_status(:redirect)
      expect(response).to redirect_to("/admin/orders/#{order.to_param}")
    end

    it 'falls back to the orders index for unknown ids' do
      get '/admin/orders/definitely-not-an-order'

      expect(response).to have_http_status(:redirect)
      expect(response).to redirect_to('/admin/orders')
    end
  end
end

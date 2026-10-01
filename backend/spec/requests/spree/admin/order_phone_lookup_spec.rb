# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin New Order phone lookup', type: :request do
  let(:admin_user) { create(:admin_user) }

  before { login_as(admin_user, scope: :admin_user) }

  let!(:customer) do
    create(:user, email: 'phonebuyer@example.com', phone: '9841000001')
  end

  def create_order(params)
    post '/admin/orders', params: { order: params }
  end

  it 'links the order to the customer found by phone' do
    expect { create_order(email: '', phone: '9841000001') }.
      to change { Spree::Order.count }.by(1)

    order = Spree::Order.last
    expect(response).to redirect_to("/admin/orders/#{order.to_param}/edit")
    expect(order.user).to eq(customer)
    expect(order.email).to eq('phonebuyer@example.com')
  end

  it 'matches stored formats with spaces and the +977 prefix' do
    customer.update!(phone: '+977 9841000001')

    expect { create_order(email: '', phone: '+9779841000001') }.
      to change { Spree::Order.count }.by(1)

    expect(Spree::Order.last.user).to eq(customer)
  end

  it 'prefers an explicitly selected customer over the phone lookup' do
    other = create(:user, email: 'other@example.com')

    expect { create_order(email: '', user_id: other.id, phone: '9841000001') }.
      to change { Spree::Order.count }.by(1)

    expect(Spree::Order.last.user).to eq(other)
  end

  it 'redirects to New User with phone and email prefilled when no customer matches' do
    expect { create_order(email: 'guest@example.com', phone: '9800000000') }.
      not_to(change { Spree::Order.count })

    expect(response).to redirect_to(
      '/admin/users/new?user%5Bemail%5D=guest%40example.com&user%5Bphone%5D=9800000000'
    )
    follow_redirect!
    expect(response.body).to include('value="9800000000"')
    expect(response.body).to include('value="guest@example.com"')
    expect(response.body).to include('No customer found with phone 9800000000')
  end

  it 'keeps the email-only flow working when no phone is typed' do
    expect { create_order(email: 'guest@example.com', phone: '') }.
      to change { Spree::Order.count }.by(1)

    order = Spree::Order.last
    expect(order.user).to be_nil
    expect(order.email).to eq('guest@example.com')
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin New User phone requirement', type: :request do
  let(:admin_user) { create(:admin_user) }

  before { login_as(admin_user, scope: :admin_user) }

  def create_user(params)
    post '/admin/users', params: { user: params }
  end

  let(:valid_params) do
    {
      email: 'newcustomer@example.com',
      first_name: 'New',
      last_name: 'Customer',
      phone: '9841000001'
    }
  end

  it 'creates the customer when a phone number is provided' do
    expect { create_user(valid_params) }.to change { Spree.user_class.count }.by(1)

    customer = Spree.user_class.find_by!(email: 'newcustomer@example.com')
    expect(customer.phone).to eq('9841000001')
    expect(response).to redirect_to("/admin/users/#{customer.to_param}")
  end

  it 'leaves email blank when omitted' do
    expect do
      create_user(valid_params.merge(email: ''))
    end.to change { Spree.user_class.count }.by(1)

    customer = Spree.user_class.find_by!(phone: '9841000001')
    expect(customer.email).to be_nil
  end

  it 're-renders the form with an error when phone is missing' do
    expect { create_user(valid_params.except(:phone)) }.
      not_to(change { Spree.user_class.count })

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('formError">can&#39;t be blank')
  end

  it 'marks phone required and email optional on the New User form' do
    get '/admin/users/new'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('required="required" class="form-input" type="text" name="user[phone]"')
    expect(response.body).not_to include('required="required" class="form-input" type="email"')
  end

  it 'prefills phone and email from query params (New Order redirect)' do
    get '/admin/users/new', params: { user: { phone: '9800000000', email: 'guest@example.com' } }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('value="9800000000"')
    expect(response.body).to include('value="guest@example.com"')
  end

  it 'leaves editing an existing phoneless user untouched' do
    phoneless = create(:user, email: 'legacy@example.com', phone: nil)

    patch "/admin/users/#{phoneless.to_param}",
          params: { user: { first_name: 'Legacy2', phone: '' } }

    expect(response).to be_redirect
    expect(phoneless.reload.first_name).to eq('Legacy2')
  end
end

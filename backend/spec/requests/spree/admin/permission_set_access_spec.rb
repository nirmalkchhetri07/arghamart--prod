# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin permission-set access', type: :request do
  let(:store) { @default_store }

  def sign_in_with_set(set_name)
    @role_counter = (@role_counter || 0) + 1
    role = create(:role, name: "#{set_name.underscore} role #{@role_counter}", permission_set_names: [set_name])
    admin_user = create(:admin_user, :without_admin_role)
    create(:role_user, user: admin_user, role: role, store: store, resource: store)
    login_as(admin_user, scope: :admin_user)
  end

  it 'allows GeographyManagement to open Nepal geography' do
    Spree::NepalGeography.seed!
    sign_in_with_set('GeographyManagement')

    get '/admin/manage-address'

    expect(response).to have_http_status(:ok)
  end

  it 'allows ReportDisplay to open reports' do
    sign_in_with_set('ReportDisplay')

    get '/admin/reports'

    expect(response).to have_http_status(:ok)
  end

  it 'allows IntegrationManagement to open Social Login and API keys' do
    sign_in_with_set('IntegrationManagement')

    get '/admin/social-login'
    expect(response).to have_http_status(:ok)

    get '/admin/api_keys'
    expect(response).to have_http_status(:ok)
  end

  it 'allows InvitationManagement to open invitations' do
    sign_in_with_set('InvitationManagement')

    get '/admin/invitations'

    expect(response).to have_http_status(:ok)
  end

  it 'allows the existing management sets to open their newly covered resources' do
    [
      ['StockManagement', '/admin/stock_transfers'],
      ['OrderManagement', '/admin/store_credit_categories'],
      ['UserManagement', '/admin/customer_groups'],
      ['UserManagement', '/admin/newsletter_subscribers']
    ].each do |set_name, path|
      sign_in_with_set(set_name)
      get path
      expect(response).to have_http_status(:ok), "expected #{set_name} to access #{path}"
      logout(:admin_user)
    end
  end
end

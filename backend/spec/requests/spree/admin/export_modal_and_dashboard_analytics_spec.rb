# frozen_string_literal: true

require 'rails_helper'

# Regression: two eagerly-loaded spree_admin turbo frames hit authorize_admin
# with no matching grant for non-superuser roles, so every navigation flashed
# "Authorization Failure":
#   * shared/_export_modal fetched /admin/exports/new from every index table
#     even though Spree::Export belongs to no permission set (and the Export
#     button itself is gated on can?(:create, Spree::Export));
#   * dashboard/show fetched /admin/dashboard/analytics even though no core
#     set grants :analytics (only SuperUser's `can :all` did).
RSpec.describe 'Non-superuser eager admin frames', type: :request do
  let(:store) { @default_store }

  def sign_in_with_set(set_name)
    @role_counter = (@role_counter || 0) + 1
    role = create(:role, name: "#{set_name.underscore} frame role #{@role_counter}", permission_set_names: [set_name])
    admin_user = create(:admin_user, :without_admin_role)
    create(:role_user, user: admin_user, role: role, store: store, resource: store)
    login_as(admin_user, scope: :admin_user)
  end

  describe 'the export dialog frame' do
    it 'is omitted for a role without Spree::Export' do
      sign_in_with_set('UserManagement')

      get '/admin/users'

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('id="export_dialog"')
    end

    it 'still renders for the superuser' do
      login_as(create(:admin_user), scope: :admin_user)

      get '/admin/users'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="export_dialog"')
    end
  end

  describe 'the dashboard analytics frame' do
    it 'loads for a role with only DashboardDisplay' do
      sign_in_with_set('DashboardDisplay')

      get '/admin/dashboard/analytics'

      expect(response).to have_http_status(:ok)
    end

    it 'shows the embedded frame on Home without a redirect loop' do
      sign_in_with_set('DashboardDisplay')

      get '/admin'

      expect(response).to have_http_status(:ok)
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin roles', type: :request do
  let(:admin_user) { create(:admin_user) }

  before { login_as(admin_user, scope: :admin_user) }

  it 'persists the implied OrderDisplay set with OrderManagement' do
    role = create(:role, name: 'order manager')

    patch spree.admin_role_path(role), params: {
      role: {
        name: role.name,
        permission_set_names: ['', 'OrderManagement', 'OrderDisplay']
      }
    }

    expect(response).to redirect_to(spree.edit_admin_role_path(role))
    expect(role.reload.selected_permission_sets).to include('OrderManagement', 'OrderDisplay')
  end
end
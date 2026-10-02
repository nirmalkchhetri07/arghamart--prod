# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spree::RolePermissions, type: :model do
  it 'has metadata for every registered permission set' do
    expect(described_class::META.keys).to match_array(described_class::SETS.keys)
  end

  it 'keeps implied display permissions in the persisted selection' do
    role = create(:role, name: 'order manager', permission_set_names: %w[OrderManagement OrderDisplay])

    expect(role.reload.selected_permission_sets).to include('OrderManagement', 'OrderDisplay')
  end
end
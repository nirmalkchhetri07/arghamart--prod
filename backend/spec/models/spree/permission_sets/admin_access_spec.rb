# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'admin access permission sets', type: :model do
  def ability_for(set_name)
    ability = Class.new { include CanCan::Ability }.new
    Spree::RolePermissions::SETS.fetch(set_name).new(ability).activate!
    ability
  end

  it 'has non-empty metadata for every registered set' do
    expect(Spree::RolePermissions::META.keys).to match_array(Spree::RolePermissions::SETS.keys)
    expect(Spree::RolePermissions::META.values).to all(include(:label, :group, :areas))
    expect(Spree::RolePermissions::META.values.map { |metadata| metadata[:areas] }).to all(be_present)
  end

  it 'grants each requested area through its focused set' do
    expect(ability_for('StockManagement').can?(:manage, Spree::StockTransfer)).to be(true)
    expect(ability_for('OrderManagement').can?(:manage, Spree::StoreCreditCategory)).to be(true)
    expect(ability_for('OrderManagement').can?(:manage, Spree::GiftCardBatch)).to be(true)
    expect(ability_for('UserManagement').can?(:manage, Spree::CustomerGroup)).to be(true)
    expect(ability_for('UserManagement').can?(:manage, Spree::NewsletterSubscriber)).to be(true)
    expect(ability_for('ReportDisplay').can?(:read, Spree::Report)).to be(true)
    expect(ability_for('GeographyManagement').can?(:manage, Spree::Country)).to be(true)
    expect(ability_for('GeographyManagement').can?(:manage, Spree::State)).to be(true)
    expect(ability_for('GeographyManagement').can?(:manage, Spree::District)).to be(true)
    expect(ability_for('IntegrationManagement').can?(:manage, Spree::OauthProvider)).to be(true)
    expect(ability_for('IntegrationManagement').can?(:manage, Spree::ApiKey)).to be(true)
    expect(ability_for('InvitationManagement').can?(:manage, Spree::Invitation)).to be(true)
  end

  it 'does not include invitation or integration access in manager or staff' do
    %w[manager staff].each do |role_name|
      selected = role_name == 'manager' ? Spree::RolePermissions::MANAGER_SETS : Spree::RolePermissions::STAFF_SETS
      ability = selected.each_with_object(Class.new { include CanCan::Ability }.new) do |set_name, current|
        Spree::RolePermissions::SETS.fetch(set_name).new(current).activate!
      end

      expect(ability.can?(:manage, Spree::OauthProvider)).to be(false)
      expect(ability.can?(:manage, Spree::Invitation)).to be(false)
    end
  end

  it 'has no computed admin-only areas after all sets are activated' do
    expect(Spree::RolePermissions.admin_only_areas).to be_empty
  end
end

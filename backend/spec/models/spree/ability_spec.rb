# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spree::Ability, type: :model do
  # @default_store is set before(:all) by Spree::TestingSupport::Store and
  # is the store other request specs bind roles to.
  let(:store) { @default_store }

  # Builds an ability for a persisted user bound to +role_name+ on the
  # default store with the given permission sets selected in the admin
  # Roles form.
  def ability_for(role_name, permission_set_names)
    role = create(:role, name: role_name, permission_set_names: permission_set_names)
    user = create(:user)
    create(:role_user, user: user, role: role, store: store, resource: store)
    described_class.new(user, store: store)
  end

  it 'applies GeographyManagement grants to a role-bound user' do
    ability = ability_for('geography manager', ['GeographyManagement'])

    expect(ability.can?(:manage, Spree::Country)).to be(true)
    expect(ability.can?(:manage, Spree::District)).to be(true)
    expect(ability.can?(:manage, :districts)).to be(true)
    expect(ability.can?(:manage, Spree::Product)).to be(false)
  end

  it 'does not grant Social Login or Nepal pages to a ProductManagement-only role' do
    ability = ability_for('catalog manager', ['ProductManagement'])

    expect(ability.can?(:manage, Spree::Product)).to be(true)
    expect(ability.can?(:manage, Spree::OauthProvider)).to be(false)
    expect(ability.can?(:admin, :oauth_providers)).to be(false)
    expect(ability.can?(:manage, Spree::District)).to be(false)
  end

  it 'applies IntegrationManagement grants to a role-bound user' do
    ability = ability_for('integration manager', ['IntegrationManagement'])

    expect(ability.can?(:manage, Spree::OauthProvider)).to be(true)
    expect(ability.can?(:admin, :oauth_providers)).to be(true)
    expect(ability.can?(:manage, Spree::ApiKey)).to be(true)
  end

  it 'keeps the admin role a SuperUser' do
    user = create(:admin_user, :without_admin_role)
    create(:role_user, user: user, role: Spree::Role.default_admin_role,
                       store: store, resource: store)
    ability = described_class.new(user, store: store)

    expect(ability.can?(:manage, Spree::OauthProvider)).to be(true)
    expect(ability.can?(:manage, Spree::Product)).to be(true)
  end
end

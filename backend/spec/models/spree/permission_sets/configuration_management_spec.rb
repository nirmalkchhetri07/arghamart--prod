# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spree::PermissionSets::ConfigurationManagement, type: :model do
  # CanCan::Ability is a module — Spree::Ability includes it, but for a
  # bare ability an anonymous class works just as well.
  subject(:ability) { Class.new { include CanCan::Ability }.new }

  before { described_class.new(ability).activate! }

  it 'grants the core configuration resources' do
    expect(ability.can?(:manage, Spree::Store)).to be(true)
    expect(ability.can?(:manage, Spree::PaymentMethod)).to be(true)
    expect(ability.can?(:manage, Spree::Policy)).to be(true)
  end

  it 'is extended by the app decorator' do
    expect(described_class.ancestors).
      to include(Spree::PermissionSets::ConfigurationManagementDecorator)
  end

  it 'leaves integrations and geography to their focused permission sets' do
    expect(ability.can?(:manage, Spree::OauthProvider)).to be(false)
    expect(ability.can?(:manage, Spree::District)).to be(false)
  end

  it 'does not grant catalog or order resources' do
    expect(ability.can?(:manage, Spree::Product)).to be(false)
    expect(ability.can?(:manage, Spree::Order)).to be(false)
  end
end

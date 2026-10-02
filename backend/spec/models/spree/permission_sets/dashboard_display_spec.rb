# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spree::PermissionSets::DashboardDisplay, type: :model do
  # CanCan::Ability is a module — Spree::Ability includes it, but for a
  # bare ability an anonymous class works just as well.
  subject(:ability) { Class.new { include CanCan::Ability }.new }

  before { described_class.new(ability).activate! }

  it 'grants the dashboard pages' do
    expect(ability.can?(:admin, :dashboard)).to be(true)
    expect(ability.can?(:index, :dashboard)).to be(true)
    expect(ability.can?(:show, :dashboard)).to be(true)
  end

  it 'is extended by the app decorator' do
    expect(described_class.ancestors).
      to include(Spree::PermissionSets::DashboardDisplayDecorator)
  end

  # dashboard/show embeds the analytics turbo frame; without this grant
  # every non-superuser role flashed "Authorization Failure" on Home.
  it 'grants the analytics frame the dashboard embeds' do
    expect(ability.can?(:analytics, :dashboard)).to be(true)
  end

  it 'does not grant unrelated resources' do
    expect(ability.can?(:manage, Spree::Order)).to be(false)
    expect(ability.can?(:manage, Spree::Product)).to be(false)
  end
end

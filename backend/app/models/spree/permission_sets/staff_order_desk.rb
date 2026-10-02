# frozen_string_literal: true

module Spree
  module PermissionSets
    class StaffOrderDesk < Base
      def activate!
        Spree::PermissionSets::ProductDisplay.new(ability).activate!
        Spree::PermissionSets::UserDisplay.new(ability).activate!

        can :manage, Spree::Order
        can :manage, Spree::Payment
        can :manage, Spree::Shipment
        can :manage, Spree::Adjustment
        can :manage, Spree::LineItem

        cannot :destroy, Spree::Order
        cannot :destroy, Spree::Payment
      end
    end
  end
end

# frozen_string_literal: true

module Spree
  module RolePermissions
    SETS = {
      'ConfigurationManagement' => Spree::PermissionSets::ConfigurationManagement,
      'DashboardDisplay' => Spree::PermissionSets::DashboardDisplay,
      'OrderDisplay' => Spree::PermissionSets::OrderDisplay,
      'OrderManagement' => Spree::PermissionSets::OrderManagement,
      'ProductDisplay' => Spree::PermissionSets::ProductDisplay,
      'ProductManagement' => Spree::PermissionSets::ProductManagement,
      'PromotionManagement' => Spree::PermissionSets::PromotionManagement,
      'RoleManagement' => Spree::PermissionSets::RoleManagement,
      'StockDisplay' => Spree::PermissionSets::StockDisplay,
      'StockManagement' => Spree::PermissionSets::StockManagement,
      'UserDisplay' => Spree::PermissionSets::UserDisplay,
      'UserManagement' => Spree::PermissionSets::UserManagement,
      'StaffOrderDesk' => Spree::PermissionSets::StaffOrderDesk,
      'ReportDisplay' => Spree::PermissionSets::ReportDisplay,
      'GeographyManagement' => Spree::PermissionSets::GeographyManagement,
      'IntegrationManagement' => Spree::PermissionSets::IntegrationManagement,
      'InvitationManagement' => Spree::PermissionSets::InvitationManagement
    }.freeze

    MANAGER_SETS = %w[
      DashboardDisplay
      OrderDisplay
      OrderManagement
      ProductManagement
      PromotionManagement
      StockManagement
      UserManagement
    ].freeze

    STAFF_SETS = %w[StaffOrderDesk].freeze

    OPTIONS = SETS.keys.freeze

    META = {
      'ConfigurationManagement' => {
        label: 'Configuration Management',
        group: 'Settings',
        areas: ['Store settings', 'Payments', 'Shipping', 'Tax', 'Markets', 'Webhooks', 'Policies'],
        warning: 'Broad access to payment, shipping, tax and webhook settings.'
      },
      'DashboardDisplay' => {
        label: 'Dashboard Display', group: 'Settings', areas: ['Admin dashboard']
      },
      'OrderDisplay' => {
        label: 'Order Display', group: 'Orders', areas: ['View orders']
      },
      'OrderManagement' => {
        label: 'Order Management', group: 'Orders', areas: ['Manage orders', 'Payments', 'Shipments'],
        implies: ['OrderDisplay']
      },
      'ProductDisplay' => {
        label: 'Product Display', group: 'Catalog', areas: ['View products', 'View taxons']
      },
      'ProductManagement' => {
        label: 'Product Management', group: 'Catalog', areas: ['Manage products', 'Variants', 'Taxons'],
        implies: ['ProductDisplay']
      },
      'PromotionManagement' => {
        label: 'Promotion Management', group: 'Catalog', areas: ['Manage promotions', 'Coupons']
      },
      'RoleManagement' => {
        label: 'Role Management', group: 'People', areas: ['Manage roles', 'Assign permission sets'],
        warning: 'Can grant itself any other set; treat this role as near-admin.'
      },
      'StockDisplay' => {
        label: 'Stock Display', group: 'Catalog', areas: ['View inventory', 'Stock locations']
      },
      'StockManagement' => {
        label: 'Stock Management', group: 'Catalog', areas: ['Manage inventory', 'Stock locations', 'Stock movements'],
        implies: ['StockDisplay']
      },
      'UserDisplay' => {
        label: 'User Display', group: 'People', areas: ['View users', 'View admin users']
      },
      'UserManagement' => {
        label: 'User Management', group: 'People', areas: ['Manage users', 'Manage admin users'],
        implies: ['UserDisplay']
      },
      'StaffOrderDesk' => {
        label: 'Staff Order Desk', group: 'Orders', areas: ['Order desk', 'Order payments', 'Order shipments']
      },
      'ReportDisplay' => {
        label: 'Report Display', group: 'Reports', areas: ['View reports']
      },
      'GeographyManagement' => {
        label: 'Geography Management', group: 'Geography', areas: ['Countries', 'States', 'Zones', 'Nepal provinces', 'Nepal districts', 'District delivery fees']
      },
      'IntegrationManagement' => {
        label: 'Integration Management', group: 'Integrations', areas: ['Social Login', 'API keys'],
        warning: 'Controls login providers and API credentials. Grant only to trusted roles.'
      },
      'InvitationManagement' => {
        label: 'Invitation Management', group: 'People', areas: ['Staff invitations'],
        warning: 'Can invite new staff users. Treat as near-admin.'
      }
    }.freeze

    GROUPS = {
      'Orders' => %w[OrderDisplay OrderManagement StaffOrderDesk],
      'Catalog' => %w[ProductDisplay ProductManagement PromotionManagement StockDisplay StockManagement],
      'People' => %w[UserDisplay UserManagement RoleManagement],
      'Geography' => %w[GeographyManagement],
      'Reports' => %w[ReportDisplay],
      'Integrations' => %w[IntegrationManagement],
      'Settings' => %w[ConfigurationManagement DashboardDisplay]
    }.freeze

    AREA_ACCESS = {
      'Social Login' => [Spree::OauthProvider, :manage],
      'Nepal geography' => [Spree::District, :manage],
      'Countries & States' => [Spree::Country, :read],
      'Reports' => [Spree::Report, :read],
      'Stock transfers' => [Spree::StockTransfer, :manage],
      'Store-credit categories' => [Spree::StoreCreditCategory, :manage],
      'Gift-card batches' => [Spree::GiftCardBatch, :manage],
      'Newsletter subscribers' => [Spree::NewsletterSubscriber, :manage],
      'Customer groups' => [Spree::CustomerGroup, :manage],
      'Invitations' => [Spree::Invitation, :manage],
      'API keys' => [Spree::ApiKey, :manage]
    }.freeze

    def self.admin_only_areas
      ability = Class.new { include CanCan::Ability }.new
      SETS.each_value { |permission_set| permission_set.new(ability).activate! }
      AREA_ACCESS.filter_map do |area, (subject, action)|
        area unless ability.can?(action, subject)
      end
    end

    module RoleDecorator
      def self.prepended(base)
        base.serialize :permission_set_names, coder: JSON, type: Array
      end

      def selected_permission_sets
        Array(permission_set_names).filter { |name| OPTIONS.include?(name) }
      end
    end

    module AbilityDecorator
      protected

      def apply_permissions_from_sets
        role_names = determine_role_names
        database_sets = role_names.flat_map do |role_name|
          role = role_record_for(role_name)
          role&.selected_permission_sets.to_a
        end

        if database_sets.any?
          activate_permission_sets(database_sets.filter_map { |name| SETS[name] }.uniq)
        else
          super
        end
      end

      def role_record_for(role_name)
        return if role_name.to_s == Spree::Role::ADMIN_ROLE
        return unless @user.respond_to?(:role_users)

        @user.role_users.where(store: @store).joins(:role).
          find_by(spree_roles: { name: role_name.to_s })&.role
      end
    end
  end
end

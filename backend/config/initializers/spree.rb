# frozen_string_literal: true

# Configure Spree Preferences
#
# Note: Initializing preferences available within the Admin will overwrite any changes that were made through the user interface when you restart.
#       If you would like users to be able to update a setting with the Admin it should NOT be set here.
#
# Note: If a preference is set here it will be stored within the cache & database upon initialization.
#       Just removing an entry from this initializer will not make the preference value go away.
#       Instead you must either set a new value or remove entry, clear cache, and remove database entry.
#
# In order to initialize a setting do:
# config.setting_name = 'new value'
#
# More on configuring Spree preferences can be found at:
# https://docs.spreecommerce.org/developer/customization
Spree.config do |config|
  # Nepal-only market: phone is required on every checkout address (enforced
  # in Spree::AddressDecorator#require_phone? as well — this keeps the admin
  # UI and Spree defaults consistent). Zip stays optional via
  # #require_zipcode? override.
  config.address_requires_phone = true
end

# Configure Spree Dependencies
#
# Note: If a dependency is set here it will NOT be stored within the cache & database upon initialization.
#       Just removing an entry from this initializer will make the dependency value go away.
#
# More on how to use Spree dependencies can be found at:
# https://docs.spreecommerce.org/customization/dependencies
Spree.dependencies do |dependencies|
  # Example:
  # Uncomment to change the default Service handling adding Items to Cart
  # dependencies.cart_add_item_service = 'MyNewAwesomeService'
end

# Manual QR screenshot uploads ride the Store API as multipart bodies up to
# 5 MB — above Spree's 100 KB default API body cap, so raise it (with room
# for multipart overhead). Larger bodies still get a 413 from
# Spree::Api::Middleware::RequestSizeLimit.
Spree::Api::Config[:max_request_body_size] = 6.megabytes

Rails.application.config.after_initialize do
  require_dependency Rails.root.join('app/models/spree/permission_sets/staff_order_desk').to_s
  require_dependency Rails.root.join('app/models/spree/permission_sets/additional_admin_access').to_s
  require_dependency Rails.root.join('app/models/spree/permission_sets/configuration_management_decorator').to_s
  require_dependency Rails.root.join('app/models/spree/role_permissions').to_s
  require_dependency Rails.root.join('app/controllers/spree/admin/roles_controller_decorator').to_s
  require_dependency Rails.root.join('app/controllers/spree/admin/admin_users_controller_decorator').to_s
  require_dependency Rails.root.join('app/subscribers/ncm/order_completed_subscriber').to_s
  Spree::Role.prepend(Spree::RolePermissions::RoleDecorator)
  Spree::Ability.prepend(Spree::RolePermissions::AbilityDecorator)
  Spree::PermissionSets::StockManagement.prepend(Spree::PermissionSets::StockManagementDecorator)
  Spree::PermissionSets::OrderManagement.prepend(Spree::PermissionSets::OrderManagementDecorator)
  Spree::PermissionSets::UserManagement.prepend(Spree::PermissionSets::UserManagementDecorator)
  Spree::PermissionSets::DashboardDisplay.prepend(Spree::PermissionSets::DashboardDisplayDecorator)
  Spree::Admin::RolesController.prepend(Spree::Admin::RolesControllerDecorator)
  Spree::Admin::AdminUsersController.prepend(Spree::Admin::AdminUsersControllerDecorator)
  Spree::PermissionSets::ConfigurationManagement.prepend(Spree::PermissionSets::ConfigurationManagementDecorator)
  Spree.subscribers << Ncm::OrderCompletedSubscriber unless Spree.subscribers.include?(Ncm::OrderCompletedSubscriber)

  Rails.application.reloader.to_prepare do
    require_dependency Rails.root.join('app/models/spree/permission_sets/staff_order_desk').to_s
    require_dependency Rails.root.join('app/models/spree/permission_sets/additional_admin_access').to_s
    require_dependency Rails.root.join('app/models/spree/permission_sets/configuration_management_decorator').to_s
    require_dependency Rails.root.join('app/models/spree/role_permissions').to_s
    require_dependency Rails.root.join('app/controllers/spree/admin/roles_controller_decorator').to_s
    require_dependency Rails.root.join('app/controllers/spree/admin/admin_users_controller_decorator').to_s
    require_dependency Rails.root.join('app/subscribers/ncm/order_completed_subscriber').to_s
    Spree::Role.prepend(Spree::RolePermissions::RoleDecorator) unless Spree::Role < Spree::RolePermissions::RoleDecorator
    Spree::Ability.prepend(Spree::RolePermissions::AbilityDecorator) unless Spree::Ability < Spree::RolePermissions::AbilityDecorator
    Spree::PermissionSets::StockManagement.prepend(Spree::PermissionSets::StockManagementDecorator) unless Spree::PermissionSets::StockManagement < Spree::PermissionSets::StockManagementDecorator
    Spree::PermissionSets::OrderManagement.prepend(Spree::PermissionSets::OrderManagementDecorator) unless Spree::PermissionSets::OrderManagement < Spree::PermissionSets::OrderManagementDecorator
    Spree::PermissionSets::UserManagement.prepend(Spree::PermissionSets::UserManagementDecorator) unless Spree::PermissionSets::UserManagement < Spree::PermissionSets::UserManagementDecorator
    unless Spree::PermissionSets::DashboardDisplay < Spree::PermissionSets::DashboardDisplayDecorator
      Spree::PermissionSets::DashboardDisplay.prepend(Spree::PermissionSets::DashboardDisplayDecorator)
    end
    Spree::Admin::RolesController.prepend(Spree::Admin::RolesControllerDecorator) unless Spree::Admin::RolesController < Spree::Admin::RolesControllerDecorator
    Spree::Admin::AdminUsersController.prepend(Spree::Admin::AdminUsersControllerDecorator) unless Spree::Admin::AdminUsersController < Spree::Admin::AdminUsersControllerDecorator
    unless Spree::PermissionSets::ConfigurationManagement < Spree::PermissionSets::ConfigurationManagementDecorator
      Spree::PermissionSets::ConfigurationManagement.prepend(Spree::PermissionSets::ConfigurationManagementDecorator)
    end
  end

  Spree.payment_methods << Spree::PaymentMethod::Esewa
  Spree.payment_methods << Spree::PaymentMethod::Khalti
  Spree.payment_methods << Spree::PaymentMethod::ManualQr
  # Spree.shipping_methods << Spree::ShippingMethods::SuperExpensiveNotVeryFastShipping
  # Spree.payment_methods << Spree::PaymentMethods::VerySafeAndReliablePaymentMethod

  # Nepal district shipping (Part 5). Appended to the engine's default list
  # so it appears in the admin shipping-method calculator dropdown alongside
  # FlatRate/PerItem/etc.
  Spree.calculators.shipping_methods << Spree::Calculator::Shipping::DistrictShipping

  # Spree.calculators.tax_rates << Spree::TaxRates::FinanceTeamForcedMeToCodeThis

  # Spree.stock_splitters << Spree::Stock::Splitters::SecretLogicSplitter

  # Spree.adjusters << Spree::Adjustable::Adjuster::TaxTheRich

  # Custom promotions
  # Spree.calculators.promotion_actions_create_adjustments << Spree::Calculators::PromotionActions::CreateAdjustments::AddDiscountForFriends
  # Spree.calculators.promotion_actions_create_item_adjustments << Spree::Calculators::PromotionActions::CreateItemAdjustments::FinanceTeamForcedMeToCodeThis
  # Spree.promotions.rules << Spree::Promotions::Rules::OnlyForVIPCustomers
  # Spree.promotions.actions << Spree::Promotions::Actions::GiftWithPurchase

  # Spree.taxon_rules << Spree::TaxonRules::ProductsWithColor

  # Spree.exports << Spree::Exports::Payments
  # Spree.reports << Spree::Reports::MassivelyOvercomplexReportForCfo

  # Role-based permissions
  Spree.permissions.assign(:default, [Spree::PermissionSets::DefaultCustomer])
  Spree.permissions.assign(:admin, [Spree::PermissionSets::SuperUser])
  manager_sets = Spree::RolePermissions::MANAGER_SETS.filter_map do |name|
    Spree::RolePermissions::SETS[name]
  end
  Spree.permissions.assign(:manager, manager_sets)
  Spree.permissions.assign(:staff, [Spree::PermissionSets::StaffOrderDesk])

  # Nepal delivery pages (Parts 3-4) in the admin sidebar, between Reports
  # (60) and Integrations (80). Visible to the admin (SuperUser) role and to
  # any role with ConfigurationManagement (see the
  # permission_sets/configuration_management_decorator); staff without
  # district access simply don't see the section.
  sidebar = Spree.admin.navigation.sidebar
  sidebar.add :nepal,
              label: 'admin.nepal.section',
              url: :admin_manage_address_path,
              icon: 'map-pin',
              position: 70,
              if: -> { can?(:manage, Spree::District) } do |nepal|
    nepal.add :manage_address,
              label: 'admin.nepal.manage_address',
              url: :admin_manage_address_path,
              position: 10,
              active: -> { controller_name == 'provinces' || controller_name == 'districts' },
              if: -> { can?(:manage, Spree::District) }
    nepal.add :manage_fee,
              label: 'admin.nepal.manage_fee',
              url: :admin_manage_fee_path,
              position: 20,
              active: -> { controller_name == 'district_fees' },
              if: -> { can?(:manage, Spree::District) }
  end

  sidebar.add :delivery_partners,
              label: 'admin.delivery_partners.title',
              url: :admin_delivery_partners_path,
              icon: 'truck',
              position: 75,
              active: -> { controller_name == 'delivery_partners' },
              if: -> { can?(:manage, Spree::DeliveryPartner) }

  # Same pages inside Settings (admin/settings area). The main sidebar
  # switches to the settings nav when a SettingsConcern controller renders,
  # so without these the pages are only reachable by direct URL once the
  # user clicks "Settings". Positioned between Zones (80) and Shipping (90).
  settings_nav = Spree.admin.navigation.settings
  settings_nav.add :manage_address,
                   label: 'admin.nepal.manage_address',
                   url: :admin_manage_address_path,
                   icon: 'map-pin',
                   position: 85,
                   active: -> { controller_name == 'provinces' || controller_name == 'districts' },
                   if: -> { can?(:manage, Spree::District) }
  settings_nav.add :manage_fee,
                   label: 'admin.nepal.manage_fee',
                   url: :admin_manage_fee_path,
                   icon: 'coins',
                   position: 86,
                   active: -> { controller_name == 'district_fees' },
                   if: -> { can?(:manage, Spree::District) }
  settings_nav.add :social_login,
                   label: 'admin.oauth.title',
                   url: :admin_social_login_path,
                   icon: 'key',
                   position: 87,
                   active: -> { controller_name == 'oauth_providers' },
                   if: -> { can?(:manage, Spree::OauthProvider) }
  settings_nav.add :delivery_partners,
                   label: 'admin.delivery_partners.title',
                   url: :admin_delivery_partners_path,
                   icon: 'truck',
                   position: 88,
                   active: -> { controller_name == 'delivery_partners' },
                   if: -> { can?(:manage, Spree::DeliveryPartner) }

  # Keep navigation visibility aligned with the focused permission sets.
  sidebar.update :reports, if: -> { can?(:read, Spree::Report) || can?(:manage, Spree::Report) }
  settings_nav.update :zones, if: -> {
    can?(:manage, Spree::Zone) || can?(:manage, Spree::Country) || can?(:manage, Spree::State)
  }
  sidebar.update :promotions, if: -> {
    can?(:manage, Spree::Promotion) || can?(:manage, Spree::GiftCardBatch)
  }
  sidebar.update :newsletter_subscribers, if: -> { can?(:manage, Spree::NewsletterSubscriber) }
  sidebar.update :gift_cards, if: -> { can?(:manage, Spree::GiftCard) || can?(:manage, Spree::GiftCardBatch) }
end

Spree.user_class = 'Spree::User'
Spree.admin_user_class = 'Spree::AdminUser'

# Serve Active Storage attachment URLs (product images, logos, etc.) from a CDN
# host instead of the application host. Host only, no protocol — the scheme
# comes from routes.default_url_options (see config/environments/production.rb).
Spree.cdn_host = ENV['CDN_HOST'] if ENV['CDN_HOST'].present?

# Background job queue configuration
Spree.queues.default = :default
Spree.queues.events = :spree_events
Spree.queues.exports = :spree_exports
Spree.queues.images = :spree_images
Spree.queues.imports = :spree_imports
Spree.queues.products = :spree_products
Spree.queues.reports = :spree_reports
Spree.queues.variants = :spree_variants
Spree.queues.taxons = :spree_taxons
Spree.queues.stock_location_stock_items = :spree_stock_location_stock_items
Spree.queues.coupon_codes = :spree_coupon_codes
Spree.queues.addresses = :spree_addresses
Spree.queues.gift_cards = :spree_gift_cards
Spree.queues.webhooks = :spree_webhooks
Spree.queues.payment_webhooks = :spree_payment_webhooks
Spree.queues.api_keys = :spree_api_keys
Spree.queues.search = :spree_search

# Search provider
if ENV['MEILISEARCH_URL'].present?
  Spree.search_provider = 'Spree::SearchProvider::Meilisearch'
end

Rails.application.config.to_prepare do
  require_dependency 'spree/authentication_helpers'
end

Devise.parent_controller = 'Spree::BaseController' if defined?(Devise) && Devise.respond_to?(:parent_controller)

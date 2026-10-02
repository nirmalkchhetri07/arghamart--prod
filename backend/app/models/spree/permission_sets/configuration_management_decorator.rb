# frozen_string_literal: true

module Spree
  module PermissionSets
    # Extends the core ConfigurationManagement set with this app's custom
    # Settings resources, so a non-admin role that manages configuration can
    # reach them instead of only the admin (SuperUser) role:
    #
    # Spree::Admin::BaseController#authorize_admin authorizes against
    # `controller_name.to_sym` when a controller does not define
    # `model_class`, so the controller symbols are granted alongside the
    # model classes: the classes satisfy the sidebar `can?` guards, the
    # symbols satisfy the controller's `authorize!` calls.
    #   * Integrations (Settings -> Integrations)
    #   * Geography settings (Settings -> manage-address / manage-fee)
    module ConfigurationManagementDecorator
      def activate!
        # spree_core 5.6.1 grants `can :manage, Spree::ReturnReason`, but
        # that model was renamed to Spree::ReturnAuthorizationReason and
        # the old constant no longer exists — activating the core set
        # raised NameError, so no role could ever tick this box. Re-point
        # the old name on every activation so a Zeitwerk reload can't
        # leave this alias holding a stale class object.
        Spree.send(:remove_const, :ReturnReason) if Spree.const_defined?(:ReturnReason, false)
        Spree.const_set(:ReturnReason, Spree::ReturnAuthorizationReason)

        super

      end
    end
  end
end

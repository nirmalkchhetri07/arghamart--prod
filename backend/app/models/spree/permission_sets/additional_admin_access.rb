# frozen_string_literal: true

module Spree
  module PermissionSets
    module AdditionalAdminAccess
    end

    class ReportDisplay < Base
      def activate!
        can :read, Spree::Report
        can [:admin, :index, :show], Spree::Report
      end
    end

    class GeographyManagement < Base
      def activate!
        can :manage, [Spree::Country, Spree::State, Spree::Zone]
        can :manage, [Spree::Province, Spree::District]
        can :manage, %i[countries states zones provinces districts district_fees]
      end
    end

    class IntegrationManagement < Base
      def activate!
        can :manage, Spree::OauthProvider
        can :manage, Spree::ApiKey
        can :manage, :oauth_providers
      end
    end

    class InvitationManagement < Base
      def activate!
        can :manage, Spree::Invitation
        can :manage, Spree::Store
      end
    end

    module StockManagementDecorator
      def activate!
        super
        can :manage, Spree::StockTransfer
      end
    end

    module OrderManagementDecorator
      def activate!
        super
        can :manage, [Spree::StoreCreditCategory, Spree::GiftCardBatch]
      end
    end

    module UserManagementDecorator
      def activate!
        super
        can :manage, [Spree::CustomerGroup, Spree::NewsletterSubscriber]
      end
    end

    # DashboardDisplay only grants [:admin, :index, :show] for :dashboard,
    # but dashboard/show embeds the analytics turbo frame
    # (GET /admin/dashboard/analytics), which authorize_admin checks as
    # `authorize! :analytics, :dashboard`. No core set grants :analytics —
    # only SuperUser's `can :all` covered it — so any role that could see
    # the dashboard got a 302 and an "Authorization Failure" flash the
    # moment Home loaded. Anyone who may see the dashboard may see its
    # analytics section.
    module DashboardDisplayDecorator
      def activate!
        super
        can :analytics, :dashboard
      end
    end
  end
end

# frozen_string_literal: true

module Spree
  module Admin
    # Node equivalent: admin route handler for delivery partner settings.
    class DeliveryPartnersController < Spree::Admin::BaseController
      include Spree::Admin::SettingsConcern

      before_action :authorize_delivery_partners
      before_action :load_partner

      def index
      end

      def edit
      end

      def update
        attrs = delivery_partner_params
        attrs.delete(:sandbox_api_token) if attrs[:sandbox_api_token].blank?
        attrs.delete(:production_api_token) if attrs[:production_api_token].blank?

        if @partner.update(attrs)
          flash[:success] = Spree.t('admin.delivery_partners.updated')
          redirect_to spree.admin_delivery_partners_path
        else
          flash.now[:error] = @partner.errors.full_messages.to_sentence
          render :edit, status: :unprocessable_content
        end
      end

      def test_connection
        client = Ncm::Client.new(environment: @partner.environment, api_token: @partner.api_token)
        @partner.update!(branch_options: Array(client.branches))
        flash[:success] = Spree.t('admin.delivery_partners.connection_succeeded')
      rescue Ncm::Client::Error => e
        flash[:error] = e.message
      ensure
        redirect_to spree.edit_admin_delivery_partner_path(@partner.provider)
      end

      private

      def authorize_delivery_partners
        authorize! :manage, Spree::DeliveryPartner
      end

      def load_partner
        @partner = Spree::DeliveryPartner.find_or_initialize_by(provider: 'ncm')
      end

      def delivery_partner_params
        params.require(:delivery_partner).permit(
          :environment,
          :sandbox_api_token,
          :production_api_token,
          :default_pickup_branch,
          :active
        )
      end
    end
  end
end
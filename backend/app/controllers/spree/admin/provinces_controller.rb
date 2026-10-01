# frozen_string_literal: true

# Serves /admin/manage-address (Part 3): provinces with their districts.
#
# Provinces are fixed reference data (the 7 are seeded) — index is
# view-only except for renaming the display name via #update. District
# mutations live in DistrictsController; this controller only lists.
module Spree
  module Admin
    class ProvincesController < Spree::Admin::BaseController
      include Spree::Admin::SettingsConcern

      before_action :load_provinces, only: :index

      # GET /admin/manage-address
      def index
        # @provinces set by before_action, ordered by position.
      end

      # PATCH /admin/provinces/:id — rename the display name only.
      def update
        @province = Spree::Province.find_by_prefix_id!(params[:id])

        if @province.update(province_params)
          flash[:success] = Spree.t('admin.nepal.province_updated')
        else
          flash[:error] = @province.errors.full_messages.to_sentence
        end
        redirect_to spree.admin_manage_address_path
      end

      private

      def load_provinces
        @provinces = Spree::Province.includes(:districts).order(:position, :name)
      end

      def province_params
        params.require(:province).permit(:name)
      end
    end
  end
end

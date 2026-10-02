# frozen_string_literal: true

# District CRUD for /admin/manage-address (Part 3).
#
# Deletion uses `dependent: :restrict_with_error` on the associations, so a
# district referenced by addresses (via Spree::Address) refuses to delete —
# the error suggests deactivating instead, which hides it from the
# storefront dropdown without breaking history.
module Spree
  module Admin
    class DistrictsController < Spree::Admin::BaseController
      include Spree::Admin::SettingsConcern

      before_action :load_district, only: %i[update destroy activate deactivate]

      # POST /admin/districts
      def create
        @district = Spree::District.new(district_params)

        if @district.save
          flash[:success] = Spree.t('admin.nepal.district_created')
        else
          flash[:error] = @district.errors.full_messages.to_sentence
        end
        redirect_to spree.admin_manage_address_path
      end

      # PATCH /admin/districts/:id — rename and/or toggle active.
      def update
        if @district.update(district_params)
          flash[:success] = Spree.t('admin.nepal.district_updated')
        else
          flash[:error] = @district.errors.full_messages.to_sentence
        end
        redirect_to spree.admin_manage_address_path
      end

      # DELETE /admin/districts/:id
      def destroy
        @district.destroy
        if @district.destroyed?
          flash[:success] = Spree.t('admin.nepal.district_deleted')
        else
          flash[:error] = [
            @district.errors.full_messages.to_sentence.presence,
            Spree.t('admin.nepal.district_delete_blocked_hint')
          ].compact.join(' ')
        end
        redirect_to spree.admin_manage_address_path
      end

      # POST /admin/districts/:id/activate
      def activate
        @district.update!(active: true)
        flash[:success] = Spree.t('admin.nepal.district_activated')
        redirect_to spree.admin_manage_address_path
      end

      # POST /admin/districts/:id/deactivate
      def deactivate
        @district.update!(active: false)
        flash[:success] = Spree.t('admin.nepal.district_deactivated')
        redirect_to spree.admin_manage_address_path
      end

      private

      def load_district
        @district = Spree::District.find_by_prefix_id!(params[:id])
      end

      def district_params
        params.require(:district).permit(:name, :province_id, :active, :shipping_fee, :ncm_branch)
      end
    end
  end
end

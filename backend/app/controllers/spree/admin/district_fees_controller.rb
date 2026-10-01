# frozen_string_literal: true

# Serves /admin/manage-fee (Part 4): every district with its province and
# shipping fee, plus the calculator's default fee.
#
# Actions:
# - index: filter by province (?province_id=), search by name (?q=).
# - update: single-row fee edit.
# - bulk_update: many fees in one submit ({ fees: { dist_id => amount } }).
# - set_province_fee: "set fee for the whole province" shortcut.
# - update_default_fee: edits the DistrictShipping calculator's default_fee.
module Spree
  module Admin
    class DistrictFeesController < Spree::Admin::BaseController
      include Spree::Admin::SettingsConcern

      before_action :load_filters, only: :index
      before_action :load_calculator, only: %i[index update_default_fee]

      # GET /admin/manage-fee
      def index
        @districts = Spree::District.includes(:province).ordered
        @districts = @districts.where(province_id: @province_id) if @province_id.present?
        @districts = @districts.where('spree_districts.name ILIKE ?', "%#{@query.strip}%") if @query.present?
        @provinces = Spree::Province.order(:position, :name)
      end

      # PATCH /admin/district_fees/:id — single fee edit. Accepts either
      # { district: { shipping_fee } } (direct) or { fees: { id => fee } }
      # (per-row save button inside the bulk form, via formaction).
      def update
        @district = Spree::District.find_by_prefix_id!(params[:id])
        fee = params.dig(:fees, params[:id].to_s) || fee_params[:shipping_fee]

        if @district.update(shipping_fee: fee)
          flash[:success] = Spree.t('admin.nepal.fee_updated')
        else
          flash[:error] = @district.errors.full_messages.to_sentence
        end
        redirect_to redirect_back_path
      end

      # POST /admin/district_fees/bulk_update — { fees: { id => amount } }.
      def bulk_update
        fees = params.fetch(:fees, {}).permit!.to_h
        failures = []

        Spree::District.where(id: fees.keys).find_each do |district|
          failures << "#{district.name}: #{district.errors.full_messages.to_sentence}" unless district.update(shipping_fee: fees[district.id.to_s])
        end

        if failures.empty?
          flash[:success] = Spree.t('admin.nepal.fees_bulk_updated')
        else
          flash[:error] = failures.join('; ')
        end
        redirect_to redirect_back_path
      end

      # POST /admin/district_fees/set_province_fee — one fee for a province.
      # Accepts integer or prefixed province IDs (admin selects send integers).
      def set_province_fee
        province = find_province(params[:province_id])
        fee = params[:shipping_fee]

        invalid = fee.blank? || BigDecimal(fee.to_s, exception: false).nil? || fee.to_d.negative?
        if invalid
          flash[:error] = Spree.t('admin.nepal.fee_invalid')
        else
          province.districts.update_all(shipping_fee: fee.to_d, updated_at: Time.current)
          flash[:success] = Spree.t('admin.nepal.province_fee_updated', province: province.name)
        end
        redirect_to redirect_back_path
      end

      # POST /admin/district_fees/update_default_fee — calculator fallback.
      def update_default_fee
        if @calculator.nil?
          flash[:error] = Spree.t('admin.nepal.no_district_calculator')
        elsif @calculator.update(preferred_default_fee: params[:default_fee])
          flash[:success] = Spree.t('admin.nepal.default_fee_updated')
        else
          flash[:error] = @calculator.errors.full_messages.to_sentence
        end
        redirect_to spree.admin_manage_fee_path
      end

      private

      def load_filters
        @province_id = params[:province_id].presence
        @province_id = find_province(@province_id)&.id.to_s if @province_id&.start_with?('prov_')
        @query = params[:q].presence
      end

      def load_calculator
        method = Spree::ShippingMethod.joins(:calculator).
                 where(spree_calculators: { type: 'Spree::Calculator::Shipping::DistrictShipping' }).
                 first
        @calculator = method&.calculator
        @shipping_method = method
      end

      def fee_params
        params.require(:district).permit(:shipping_fee)
      end

      def redirect_back_path
        spree.admin_manage_fee_path(province_id: params[:province_id].presence, q: params[:q].presence)
      end

      # Admin selects send integer IDs; API-style callers may send prefixed
      # IDs. Accept both so forms and specs share the same endpoint.
      def find_province(value)
        return nil if value.blank?

        str = value.to_s
        if str.start_with?('prov_')
          Spree::Province.find_by_prefix_id!(str)
        else
          Spree::Province.find(str)
        end
      end
    end
  end
end

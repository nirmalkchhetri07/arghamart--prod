# frozen_string_literal: true

# Spree 5.6 looks admin orders up by Stripe-style prefixed ID
# (e.g. /admin/orders/or_VqXmZF31wY), while staff still refer to orders by
# their human-readable legacy number (e.g. R672084530, shown in the UI).
# Hitting the detail page with the legacy number raises RecordNotFound and
# lands on the orders index, which looks like the page "doesn't render".
#
# This bridges the two: on RecordNotFound, retry the lookup by legacy
# number within the current store and redirect to the canonical prefixed
# URL when it matches. Anything else falls through to Spree's stock
# not-found handling (redirect to the orders index with an error flash).
module Spree
  module Admin
    module OrdersControllerDecorator
      def self.prepended(base)
        base.rescue_from ActiveRecord::RecordNotFound, with: :redirect_legacy_order_number
      end

      # New Order phone lookup: when no customer is selected but a phone
      # number is typed, resolve it to a customer account before the order
      # is built. Phone numbers identify customers more reliably than email
      # in Nepal. An explicitly selected customer always wins; an unknown
      # phone redirects to New User with the phone (and typed email)
      # prefilled so staff can create the account in one hop.
      def create
        if params[:order].present?
          phone = params[:order].delete(:phone).to_s.strip

          if params[:order][:user_id].blank? && phone.present?
            customer = find_customer_by_phone(phone)

            if customer
              params[:order][:user_id] = customer.id
              params[:order][:email] = customer.email if params[:order][:email].blank?
            else
              prefill = { phone: phone }
              typed_email = params[:order][:email].to_s.strip
              prefill[:email] = typed_email if typed_email.present?
              flash[:notice] = I18n.t('spree.admin.orders.no_customer_found_redirect', phone: phone)
              redirect_to spree.new_admin_user_path(user: prefill) and return
            end
          end
        end

        super
      end

      private

      # Digits only, with a leading Nepali country code dropped, so stored
      # formats ("+977 9849114740") and typed ones ("9849114740",
      # "+9779849114740") all match. Matched as a suffix so mobile and
      # landline lengths both work.
      def normalize_phone_for_lookup(value)
        digits = value.to_s.gsub(/\D/, '')
        digits = digits.sub(/\A977/, '') if digits.length > 10 && digits.start_with?('977')
        digits
      end

      def find_customer_by_phone(phone)
        digits = normalize_phone_for_lookup(phone)
        return nil if digits.blank?

        Spree.user_class.where.not(phone: [nil, '']).
          where("regexp_replace(phone, '\\D', '', 'g') LIKE ?", "%#{digits}").
          order(updated_at: :desc).first
      end

      def redirect_legacy_order_number
        order = params[:id].present? && current_store.orders.find_by(number: params[:id])

        if order
          redirect_to spree.admin_order_path(order)
        else
          resource_not_found
        end
      end
    end

    OrdersController.prepend OrdersControllerDecorator
  end
end

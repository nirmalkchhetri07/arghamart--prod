# frozen_string_literal: true

# Permits the Manual QR image upload on the admin payment-method form (see
# app/views/spree/admin/payment_methods/custom_form_fields/_manual_qr) and
# surfaces storage failures (Cloudflare R2 in production) as a flash message
# instead of an unhandled 500 — without this the admin only sees the generic
# error page and never learns that the bucket rejected the write.
module Spree
  module Admin
    module PaymentMethodsControllerDecorator
      def create
        super
      rescue StandardError => e
        handle_image_storage_failure(e)
      end

      def update
        super
      rescue StandardError => e
        handle_image_storage_failure(e)
      end

      private

      def handle_image_storage_failure(exception)
        Rails.error.report(
          exception,
          context: { payment_method_id: @object&.id, request_id: request.request_id },
          source: 'admin.payment_method_image_upload'
        )
        Rails.logger.error(
          "[manual_qr] payment-method image upload failed (#{request.request_id}): " \
          "#{exception.class}: #{exception.message}"
        )
        discard_failed_image_upload

        flash[:error] = Spree.t('admin.manual_qr.image_upload_failed', error: exception.message)
        if @object&.persisted?
          redirect_to location_after_save, status: :see_other
        else
          redirect_to collection_url, status: :see_other
        end
      end

      # Active Storage commits the attachment row first and uploads in an
      # after_commit callback, so a rejected upload leaves `attached?` true
      # with no file behind it — drop that row before telling the admin.
      def discard_failed_image_upload
        @object.qr_image.purge if @object&.qr_image&.attached?
      rescue StandardError => e
        Rails.logger.warn(
          "[manual_qr] could not discard failed QR image upload: #{e.class}: #{e.message}"
        )
      end

      def permitted_resource_params
        params.require(:payment_method).permit(
          permitted_payment_method_attributes +
            @object.preferences.keys.map { |key| "preferred_#{key}" } +
            [:qr_image]
        )
      end
    end
  end
end

Spree::Admin::PaymentMethodsController.prepend Spree::Admin::PaymentMethodsControllerDecorator

# frozen_string_literal: true

# Manual QR review actions layered on the stock admin payments controller.
#
# Approve completes a pending payment (money was verified against the
# screenshot). Reject voids it with a reason so the customer sees "rejected"
# and can upload a new screenshot, which creates a fresh pending payment.
module Spree
  module Admin
    module PaymentsControllerDecorator
      def approve
        if @payment.pending? && @payment.manual_qr?
          @payment.complete!
          flash[:success] = Spree.t('admin.manual_qr.approved')
        else
          flash[:error] = Spree.t('admin.manual_qr.cannot_approve')
        end
        redirect_to location_after_save
      end

      def reject
        if @payment.pending? && @payment.manual_qr?
          @payment.update!(qr_rejection_reason: params.dig(:payment, :qr_rejection_reason).presence)
          @payment.void!
          flash[:success] = Spree.t('admin.manual_qr.rejected')
        else
          flash[:error] = Spree.t('admin.manual_qr.cannot_reject')
        end
        redirect_to location_after_save
      end

      # Serves the proof screenshot to admins only (the admin session is the
      # authorization) by redirecting to a short-lived signed provider URL —
      # the raw blob URL is never rendered into the page.
      def proof
        unless @payment.manual_qr? && @payment.proof_image.attached?
          raise ActiveRecord::RecordNotFound
        end

        with_blob_url_options do
          redirect_to @payment.proof_image.blob.url(expires_in: 5.minutes, disposition: 'inline'),
                      allow_other_host: true
        end
      end

      private

      # Disk-service URL generation needs explicit host options (S3/R2 ignore
      # them and presign from the service config instead).
      def with_blob_url_options
        previous = ActiveStorage::Current.url_options
        ActiveStorage::Current.url_options = { protocol: request.protocol, host: request.host_with_port }
        yield
      ensure
        ActiveStorage::Current.url_options = previous
      end

      def permitted_resource_params
        params.require(:payment).permit(permitted_payment_attributes + [:qr_rejection_reason])
      end
    end
  end
end

Spree::Admin::PaymentsController.prepend Spree::Admin::PaymentsControllerDecorator

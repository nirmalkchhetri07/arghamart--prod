# frozen_string_literal: true

module Spree
  module Api
    module V3
      module Store
        # Turns a storage failure (Cloudflare R2 / S3 / local disk) during a
        # Manual QR screenshot upload into a JSON error the storefront can
        # render — without it an R2 rejection surfaces as an unhandled 500 with
        # a generic body and neither the customer nor the admin sees a reason.
        #
        # The full exception is reported to the error reporter and the log with
        # the request id; the client only gets a friendly retry message plus
        # the error class, so bucket names, endpoints and credentials never
        # leave the server.
        module ManualQrStorageErrors
          extend ActiveSupport::Concern

          private

          # Renders `error.code = storage_error` (HTTP 503 — retryable) and
          # returns the render result, so callers can `return render_storage_error(e)`.
          def render_storage_error(exception)
            Rails.error.report(
              exception,
              context: { store_id: current_store&.id, request_id: request.request_id },
              source: 'manual_qr.proof_upload'
            )
            Rails.logger.error(
              "[manual_qr] proof upload failed (#{request.request_id}): " \
              "#{exception.class}: #{exception.message}"
            )

            render_error(
              code: 'storage_error',
              message: Spree.t('api.v3.manual_qr.storage_error',
                               default: 'The screenshot could not be saved right now. Please try again in a moment.'),
              status: :service_unavailable,
              details: { 'reason' => exception.class.name }
            )
          end
        end
      end
    end
  end
end

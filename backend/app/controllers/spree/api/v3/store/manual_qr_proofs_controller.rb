# frozen_string_literal: true

module Spree
  module Api
    module V3
      module Store
        # Owner-scoped Manual QR endpoints for completed orders:
        #
        # POST /api/v3/store/orders/:order_id/manual_qr_proof
        #   (multipart: proof_image=<file>, transaction_id=<optional>)
        #   Re-upload after a rejection. Creates a fresh session + pending
        #   payment; the voided (rejected) payment stays as history.
        #
        # GET /api/v3/store/orders/:order_id/payments/:payment_id/proof
        #   Authorized proof viewing. Redirects (303) to a short-lived signed
        #   provider URL — the raw blob URL is never exposed, so proofs stay
        #   visible only to the order owner and admins.
        #
        # Authorization mirrors OrdersController: complete orders scoped to the
        # store, then CanCanCan `:show` with the order token (guests) or the
        # customer JWT (signed-in users).
        class ManualQrProofsController < Store::BaseController
          before_action :find_order!
          before_action :find_payment!, only: [:show]

          def reupload
            method = manual_qr_method
            if method.nil?
              return render_error(code: 'payment_method_unavailable',
                                            message: Spree.t('api.v3.manual_qr.method_unavailable',
                                                             default: 'Manual QR payment is not available for this order.'),
                                            status: :unprocessable_content)
            end

            unless reupload_allowed?
              return render_error(code: 'reupload_not_allowed',
                                            message: Spree.t('api.v3.manual_qr.reupload_not_allowed',
                                                             default: 'A new screenshot can only be uploaded after the previous one was rejected.'),
                                            status: :unprocessable_content)
            end

            proof = params[:proof_image]
            error = proof_error(proof)
            return render_error(code: 'invalid_proof', message: error, status: :unprocessable_content) if error

            session = method.create_payment_session(order: @order)
            session.proof_image.attach(proof)

            unless session.save
              return render_errors(session.errors)
            end

            method.complete_payment_session(
              payment_session: session,
              params: { transaction_id: params[:transaction_id] }.compact
            )

            if session.errors.empty? && session.reload.completed?
              payment = Spree::Payment.find_by!(order: @order, response_code: session.external_id)
              render json: serialize_payment(payment), status: :created
            else
              render_errors(session.errors)
            end
          end

          def show
            unless @payment.manual_qr? && @payment.proof_image.attached?
              raise ActiveRecord::RecordNotFound
            end

            with_blob_url_options do
              redirect_to @payment.proof_image.blob.url(expires_in: 5.minutes, disposition: 'inline'),
                          allow_other_host: true
            end
          end

          private

          def find_order!
            # Member routes expose the order id as :id (reupload) or :order_id
            # (nested payment proof) — accept either.
            @order = scope.find_by_prefix_id!(params[:order_id] || params[:id])
            authorize!(:show, @order, order_token)
          end

          def find_payment!
            @payment = @order.payments.find_by_prefix_id!(params[:payment_id] || params[:id])
          end

          def scope
            base = current_store.orders.complete

            if current_user.present?
              base.where(user: current_user)
            elsif order_token.present?
              base.where(token: order_token)
            else
              base.none
            end
          end

          def order_token
            request.headers['x-spree-token']
          end

          # Disk-service URL generation needs explicit host options (S3/R2
          # ignore them and presign from the service config instead).
          def with_blob_url_options
            previous = ActiveStorage::Current.url_options
            ActiveStorage::Current.url_options = { protocol: request.protocol, host: request.host_with_port }
            yield
          ensure
            ActiveStorage::Current.url_options = previous
          end

          def manual_qr_method
            latest = @order.payments.select(&:manual_qr?).max_by(&:created_at)
            method = latest&.payment_method
            return method if method.is_a?(Spree::PaymentMethod::ManualQr)

            current_store.payment_methods.find_by(type: Spree::PaymentMethod::ManualQr.sti_name)
          end

          # A re-upload is only meaningful when the latest Manual QR payment
          # was rejected (void/failed) — never while one is pending review or
          # after one was verified.
          def reupload_allowed?
            latest = @order.payments.select(&:manual_qr?).max_by(&:created_at)
            latest.present? && latest.qr_status == 'rejected'
          end

          def proof_error(proof)
            limits = Spree::PaymentMethod::ManualQr
            return Spree.t('api.v3.manual_qr.proof_missing', default: 'Payment screenshot is required.') if proof.blank?
            unless limits::PROOF_CONTENT_TYPES.include?(proof.content_type.to_s)
              return Spree.t('api.v3.manual_qr.proof_invalid_type',
                             default: 'Screenshot must be a PNG, JPG or WebP image.')
            end
            if proof.size.to_i > limits::PROOF_MAX_BYTES
              return Spree.t('api.v3.manual_qr.proof_too_big', default: 'Screenshot must be under 5 MB.')
            end

            nil
          end

          def serialize_payment(payment)
            Spree.api.payment_serializer.new(payment, params: serializer_params).to_h
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

module Spree
  module Api
    module V3
      module Store
        module Carts
          # Screenshot-proof upload for Manual QR payment sessions.
          #
          # POST /api/v3/store/carts/:cart_id/payment_sessions/:id/proof
          # (multipart: proof_image=<file>)
          #
          # Authorized exactly like the stock payment-session endpoints (store
          # publishable key + the cart's order token), so guests can upload
          # during checkout. The file is validated here for a clear 422 and
          # again by the model validations as a backstop.
          class ManualQrProofsController < Store::BaseController
            include Spree::Api::V3::CartResolvable

            before_action :find_cart!
            before_action :set_payment_session

            def create
              unless @payment_session.is_a?(Spree::PaymentSessions::ManualQr)
                return render_error(
                  code: 'payment_method_mismatch',
                  message: Spree.t('api.v3.manual_qr.not_a_manual_qr_session',
                                   default: 'Payment session is not a Manual QR session.'),
                  status: :unprocessable_content
                )
              end

              proof = params[:proof_image]
              error = proof_error(proof)
              return render_error(code: 'invalid_proof', message: error, status: :unprocessable_content) if error

              unless @payment_session.pending? || @payment_session.processing?
                return render_error(
                  code: 'session_not_active',
                  message: Spree.t('api.v3.manual_qr.session_not_active',
                                   default: 'Payment session is no longer accepting proofs.'),
                  status: :unprocessable_content
                )
              end

              @payment_session.proof_image.purge if @payment_session.proof_image.attached?
              @payment_session.proof_image.attach(proof)

              unless @payment_session.save
                return render_errors(@payment_session.errors)
              end

              render json: serialize_resource(@payment_session), status: :created
            end

            protected

            def serializer_class
              Spree.api.payment_session_serializer
            end

            private

            def set_payment_session
              @payment_session = @cart.payment_sessions.find_by_prefix_id(params[:id]) ||
                                 @cart.payment_sessions.find_by!(external_id: params[:id])
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

            def serialize_resource(resource)
              serializer_class.new(resource, params: serializer_params).to_h
            end
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

# "Delivered" tracking layered on top of Spree's shipment state machine.
#
# `delivered_at` is an independent timestamp — it is deliberately NOT a new
# `state` value. spree_shipments.state (pending/ready/shipped) is depended on
# by shipping calculators, inventory units, and order completion logic
# throughout Spree core, so delivery status lives alongside it instead.
module Spree
  module ShipmentDecorator
    class NotShippedError < StandardError; end

    def self.prepended(base)
      base.scope :delivered, -> { where.not(delivered_at: nil) }
      base.scope :undelivered, -> { where(delivered_at: nil) }

      # Allow Ransack filtering on delivered_at (admin orders index
      # "Delivered" filter) without opening up other attributes.
      base.whitelisted_ransackable_attributes =
        (base.whitelisted_ransackable_attributes || []) | %w[delivered_at]
    end

    # Returns true if the shipment has been marked as delivered.
    #
    # @return [Boolean]
    def delivered?
      delivered_at.present?
    end

    def ncm_cod_charge
      return 0.to_d unless order.payments.any? { |payment| payment.payment_method.is_a?(Spree::PaymentMethod::Check) || payment.manual_qr? }

      order.amount_due.to_d.positive? ? order.amount_due.to_d : 0.to_d
    end

    def ncm_package_description
      inventory_units.includes(variant: :product).map do |unit|
        "#{unit.variant.product.name} x#{unit.quantity}"
      end.join(', ')
    end

    def ncm_weight
      weight = inventory_units.sum { |unit| unit.variant.weight.to_d * unit.quantity.to_i }
      weight.positive? ? weight : ENV.fetch('NCM_DEFAULT_WEIGHT_KG', '1').to_d
    end

    # Marks the shipment as delivered. Only valid once the carrier has the
    # parcel, i.e. the shipment is already in the `shipped` state.
    #
    # Cash on Delivery: the courier collects cash at the door, so delivery
    # completes payment — pending COD (Check) payments on the order are
    # captured here, flipping the order to Paid together with Delivered.
    # Only pending Check payments are touched: completed/failed/void payments
    # and other gateways (eSewa/Khalti) are never modified.
    #
    # NOTE: assigns + save! instead of update! — Spree::Shipment overrides
    # update!(order) with a different signature (state recalculation).
    #
    # @raise [Spree::ShipmentDecorator::NotShippedError] if not shipped
    def mark_as_delivered!(time = Time.current)
      unless shipped?
        raise NotShippedError,
              "Cannot mark shipment #{number} as delivered unless it is shipped (current state: #{state})"
      end

      self.delivered_at = time
      save!
      capture_collect_on_delivery_payments!
      true
    end

    private

    def capture_collect_on_delivery_payments!
      order.payments.each do |payment|
        next unless payment.pending?
        next unless payment.payment_method.is_a?(Spree::PaymentMethod::Check)
        next unless payment.payment_method.can_capture?(payment)

        payment.capture!
      end
    end
  end

  Shipment.prepend ShipmentDecorator
end

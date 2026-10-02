# frozen_string_literal: true

# Node equivalent: a service module that quotes delivery using the configured route tariff.
module Ncm
  class DeliveryChargeCalculator
    class UnavailableError < StandardError; end

    def self.call(origin:, destination:, delivery_type:, weight_kg:)
      rate = Spree::NcmDeliveryRate.active.find_by(
        origin_branch: origin,
        destination_branch: destination,
        delivery_type: delivery_type
      )
      raise UnavailableError, 'No NCM delivery rate is configured for this route and delivery type' unless rate

      (rate.base_rate.to_d + (rate.per_kg_rate.to_d * BigDecimal(weight_kg.to_s))).round(2)
    end
  end
end
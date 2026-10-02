# frozen_string_literal: true

# Node equivalent: a small service module that computes the remaining COD balance.
module Ncm
  class CodCalculator
    class OverpaymentError < StandardError; end

    def initialize(order:, include_delivery_charge: true)
      @order = order
      @include_delivery_charge = include_delivery_charge
    end

    def total
      amount = decimal(@order.total)
      amount -= delivery_charge unless @include_delivery_charge
      amount
    end

    def received
      @order.payments.completed.sum { |payment| decimal(payment.amount) }
    end

    def remaining
      balance = total - received
      raise OverpaymentError, "Received amount exceeds order total by #{format_amount(-balance)} NPR" if balance.negative?

      balance
    end

    private

    def delivery_charge
      @order.shipments.sum { |shipment| decimal(shipment.cost) }
    end

    def decimal(value)
      BigDecimal(value.to_s).round(2)
    end

    def format_amount(value)
      decimal(value).to_s('F')
    end
  end
end
# frozen_string_literal: true

# Node equivalent: RSpec unit tests for the COD service module.
require 'rails_helper'

RSpec.describe Ncm::CodCalculator do
  let(:order) do
    double(total: BigDecimal('2850.00'), payments: payments, shipments: shipments)
  end
  let(:payments) { double(completed: []) }
  let(:shipments) { [double(cost: BigDecimal('99.00'))] }

  def calculator(include_delivery_charge: true)
    described_class.new(order: order, include_delivery_charge: include_delivery_charge)
  end

  it 'returns the full NPR order total when no money has been received' do
    expect(calculator.remaining).to eq(BigDecimal('2850.00'))
  end

  it 'returns zero when completed payments cover the total' do
    allow(payments).to receive(:completed).and_return([double(amount: BigDecimal('2850.00'))])

    expect(calculator.remaining).to eq(BigDecimal('0.00'))
  end

  it 'subtracts completed partial payments from the order total' do
    allow(payments).to receive(:completed).and_return([double(amount: BigDecimal('1000.00'))])

    expect(calculator.remaining).to eq(BigDecimal('1850.00'))
  end

  it 'raises when completed payments exceed the total' do
    allow(payments).to receive(:completed).and_return([double(amount: BigDecimal('2851.00'))])

    expect { calculator.remaining }.to raise_error(Ncm::CodCalculator::OverpaymentError)
  end

  it 'can exclude shipment delivery charge from COD when configured' do
    expect(calculator(include_delivery_charge: false).total).to eq(BigDecimal('2751.00'))
  end
end

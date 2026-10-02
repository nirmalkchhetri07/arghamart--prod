# frozen_string_literal: true

# Node equivalent: an ORM model for an editable route and weight-based delivery tariff.
module Spree
  class NcmDeliveryRate < Spree.base_class
    DELIVERY_TYPES = %w[Door2Door Door2Branch Branch2Door Branch2Branch].freeze

    belongs_to :origin_branch, class_name: 'Spree::NcmBranch', inverse_of: :origin_rates
    belongs_to :destination_branch, class_name: 'Spree::NcmBranch', inverse_of: :destination_rates

    validates :delivery_type, inclusion: { in: DELIVERY_TYPES }
    validates :base_rate, :per_kg_rate, numericality: { greater_than_or_equal_to: 0 }
    validates :currency, inclusion: { in: %w[NPR] }

    scope :active, -> { where(active: true) }
  end
end
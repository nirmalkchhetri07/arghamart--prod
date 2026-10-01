# frozen_string_literal: true

module Spree
  class District < Spree.base_class
    has_prefix_id :dist

    belongs_to :province,
               class_name: 'Spree::Province',
               foreign_key: :province_id,
               inverse_of: :districts

    has_many :addresses,
             class_name: 'Spree::Address',
             foreign_key: :district_id,
             inverse_of: :district,
             dependent: :restrict_with_error

    validates :name, presence: true,
                     uniqueness: { scope: :province_id, case_sensitive: false }
    validates :shipping_fee,
              presence: true,
              numericality: { greater_than_or_equal_to: 0 }

    scope :active, -> { where(active: true) }
    scope :ordered, -> { joins(:province).order('spree_provinces.position ASC, spree_districts.name ASC') }

    self.whitelisted_ransackable_attributes = %w[name active shipping_fee province_id]

    # True when a fee has been configured (non-zero). The shipping
    # calculator (Part 5) falls back to the configurable default when this
    # is false instead of failing checkout.
    def fee_configured?
      shipping_fee.to_d.positive?
    end
  end
end

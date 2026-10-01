# frozen_string_literal: true

module Spree
  class Province < Spree.base_class
    has_prefix_id :prov

    has_many :districts,
             class_name: 'Spree::District',
             foreign_key: :province_id,
             inverse_of: :province,
             dependent: :restrict_with_error

    has_many :addresses,
             class_name: 'Spree::Address',
             foreign_key: :province_id,
             inverse_of: :province,
             dependent: :nullify

    validates :name, :code, presence: true, uniqueness: { case_sensitive: false }

    default_scope { order(position: :asc, name: :asc) }

    self.whitelisted_ransackable_attributes = %w[name code position]
  end
end

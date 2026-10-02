# frozen_string_literal: true

# Node equivalent: an ORM model for a selectable NCM courier branch.
module Spree
  class NcmBranch < Spree.base_class
    has_prefix_id :ncm_branch

    belongs_to :district, class_name: 'Spree::District', optional: true
    has_many :mappings, class_name: 'Spree::NcmBranchMapping', foreign_key: :branch_id,
              dependent: :destroy, inverse_of: :branch
    has_many :origin_rates, class_name: 'Spree::NcmDeliveryRate', foreign_key: :origin_branch_id,
                            dependent: :restrict_with_error, inverse_of: :origin_branch
    has_many :destination_rates, class_name: 'Spree::NcmDeliveryRate', foreign_key: :destination_branch_id,
                                 dependent: :restrict_with_error, inverse_of: :destination_branch

    validates :name, :code, presence: true
    validates :code, uniqueness: true

    scope :active, -> { where(active: true) }
  end
end
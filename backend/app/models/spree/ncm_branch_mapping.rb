# frozen_string_literal: true

# Node equivalent: an ORM mapping model for district/municipality-to-branch resolution.
module Spree
  class NcmBranchMapping < Spree.base_class
    belongs_to :branch, class_name: 'Spree::NcmBranch', inverse_of: :mappings
    belongs_to :district, class_name: 'Spree::District'

    validates :source, inclusion: { in: %w[municipality district nearest admin] }
    validates :district_id, uniqueness: { scope: :municipality }, if: -> { municipality.blank? }

    scope :active, -> { where(active: true) }
  end
end
# frozen_string_literal: true

module Ncm
  class BranchCatalog
    DEFAULT_BRANCHES = {
      'TINK1' => 'TINKUNE',
      'POKH1' => 'POKHARA',
      'BUTW1' => 'BUTWAL',
      'DAMA1' => 'DAMAK',
      'JANA1' => 'JANAKPUR',
      'SANK1' => 'SANKHU'
    }.freeze

    def self.ensure!
      DEFAULT_BRANCHES.each do |code, name|
        branch = Spree::NcmBranch.find_or_initialize_by(code: code)
        branch.name = name
        branch.active = true
        branch.save!
      end
    end
  end
end

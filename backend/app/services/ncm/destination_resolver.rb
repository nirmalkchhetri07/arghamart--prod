# frozen_string_literal: true

# Node equivalent: a service module that maps a Nepal destination to an NCM branch.
module Ncm
  class DestinationResolver
    Result = Struct.new(:branch, :source, :reason, keyword_init: true)

    def self.call(address:)
      return Result.new(reason: 'Shipping address is missing') unless address
      return Result.new(reason: 'District is required for NCM delivery') unless address.district

      municipality = address.city.to_s.strip
      if municipality.present?
        mapping = Spree::NcmBranchMapping.active.includes(:branch).
          where(district: address.district).
          where('LOWER(municipality) = ?', municipality.downcase).
          detect { |candidate| candidate.branch.active? }
        return Result.new(branch: mapping.branch, source: 'municipality') if mapping
      end

      mapped_code = address.district.ncm_branch
      if mapped_code.present?
        branch = Spree::NcmBranch.active.where('LOWER(code) = :value OR LOWER(name) = :value', value: mapped_code.downcase).first
        return Result.new(branch: branch, source: 'district') if branch
      end

      mapping = Spree::NcmBranchMapping.active.includes(:branch).
        where(district: address.district, municipality: nil).
        order(Arel.sql("CASE source WHEN 'district' THEN 0 WHEN 'nearest' THEN 1 ELSE 2 END" )).
        detect { |candidate| candidate.branch.active? }
      return Result.new(branch: mapping.branch, source: mapping.source) if mapping

      Result.new(reason: "No active NCM destination branch is mapped to #{address.district.name}")
    end
  end
end
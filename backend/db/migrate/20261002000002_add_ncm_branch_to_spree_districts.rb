# frozen_string_literal: true

class AddNcmBranchToSpreeDistricts < ActiveRecord::Migration[8.1]
  def change
    add_column :spree_districts, :ncm_branch, :string
  end
end

# Node equivalent: database migration that adds the NCM branch mapping field.
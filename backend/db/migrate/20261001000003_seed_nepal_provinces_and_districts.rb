# frozen_string_literal: true

# Seeds the 7 provinces + 77 districts for existing databases.
# Idempotent via Spree::NepalGeography.seed! — safe to re-run.
# Fresh setups get the same data via db/seeds.rb.
class SeedNepalProvincesAndDistricts < ActiveRecord::Migration[8.1]
  def up
    Spree::NepalGeography.seed!
  end

  def down
    # Keep reference data on rollback — districts may already be referenced
    # by addresses. Remove manually via the admin manage-address page.
  end
end

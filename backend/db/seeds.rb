# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

Spree::Core::Engine.load_seed if defined?(Spree::Core)

# Nepal delivery geography (7 provinces, 77 districts). Idempotent — safe to
# re-run on every deploy. Fees default to 0 until configured in /admin/manage-fee.
Spree::NepalGeography.seed! if defined?(Spree::NepalGeography)

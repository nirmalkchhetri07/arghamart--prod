# frozen_string_literal: true

module Spree
  # Node equivalent: model/entity for persisted delivery integration settings.
  class DeliveryPartner < Spree.base_class
    PROVIDERS = %w[ncm].freeze
    ENVIRONMENTS = %w[sandbox production].freeze

    validates :provider, presence: true, inclusion: { in: PROVIDERS }, uniqueness: true
    validates :environment, presence: true, inclusion: { in: ENVIRONMENTS }
    validates :webhook_secret, presence: true
    validates :default_pickup_branch, presence: true, if: :active?
    validate :only_one_active_partner

    encrypts :sandbox_api_token, :production_api_token

    scope :active, -> { where(active: true) }

    before_validation :ensure_webhook_secret, on: :create

    def api_token
      environment == 'production' ? production_api_token : sandbox_api_token
    end

    def configured?
      sandbox_api_token.present? || production_api_token.present?
    end

    def branch_names
      Array(branch_options).filter_map do |branch|
        branch.is_a?(Hash) ? (branch['name'] || branch['branch'] || branch['branch_name']) : branch.to_s
      end.uniq.sort
    end

    private

    def ensure_webhook_secret
      self.webhook_secret = SecureRandom.hex(32) if webhook_secret.blank?
    end

    def only_one_active_partner
      return unless active? && self.class.where(active: true).where.not(id: id).exists?

      errors.add(:active, 'only one delivery partner can be active at a time')
    end
  end
end
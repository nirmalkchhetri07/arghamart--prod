# frozen_string_literal: true

# A social-login provider configured in /admin (Social Login), e.g. Google.
# Customers sign in with it via the Store API OAuth endpoints; admins add,
# edit, enable/disable and remove rows without touching code or env vars.
#
# client_secret is encrypted at rest (see
# config/initializers/active_record_encryption.rb) and never serialized.
# It is nullable because the Google ID-token flow needs only client_id;
# authorization-code providers (Facebook/GitHub when implemented) need it.
module Spree
  class OauthProvider < Spree.base_class
    validates :provider, presence: true,
                         inclusion: { in: ->(_record) { Spree::Oauth::Providers.implemented.map(&:key) } },
                         uniqueness: true
    validates :name, :client_id, presence: true

    scope :enabled, -> { where(enabled: true) }
    scope :ordered, -> { order(position: :asc, provider: :asc) }

    encrypts :client_secret

    def verifier
      Spree::Oauth::Providers.verifier_for(provider)
    end

    def implemented?
      Spree::Oauth::Providers.implemented?(provider)
    end
  end
end

# frozen_string_literal: true

# A social-login provider configured in /admin (Social Login), e.g. Google.
# Customers sign in with it via the Store API OAuth endpoints; admins add,
# edit, enable/disable and remove rows without touching code or env vars.
#
# client_secret is encrypted at rest (see
# config/initializers/active_record_encryption.rb) and never serialized.
# It is nullable because the Google ID-token flow needs only client_id;
# the Facebook token flow and the GitHub code flow need it server-side.
module Spree
  class OauthProvider < Spree.base_class
    validates :provider, presence: true,
                         inclusion: { in: ->(_record) { Spree::Oauth::Providers.implemented.map(&:key) } },
                         uniqueness: true
    validates :name, :client_id, presence: true
    # Facebook verifies tokens with <app_id>|<app_secret> server-side, so a
    # record without a secret could never succeed. (The edit form submits a
    # blank secret to mean "keep the stored one" — the controller strips it
    # before update, so this only fires when no secret is stored.)
    validates :client_secret, presence: true, if: -> { provider == 'facebook' }

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

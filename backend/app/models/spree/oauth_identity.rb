# frozen_string_literal: true

# Links a customer account to an external identity (Google subject id, …).
# Deleting the provider row never touches users or identities (no
# `dependent` option anywhere) — orphaned rows simply stop resolving
# because login requires an enabled Spree::OauthProvider record.
module Spree
  class OauthIdentity < Spree.base_class
    belongs_to :user, class_name: Spree.user_class.to_s

    validates :provider, :uid, presence: true
    validates :uid, uniqueness: { scope: :provider }
  end
end

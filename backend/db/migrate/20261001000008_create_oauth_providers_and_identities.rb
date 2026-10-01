# frozen_string_literal: true

# Social login providers + linked identities (see Spree::OauthProvider,
# Spree::OauthIdentity). Providers are managed in /admin (Social Login);
# customers sign in with them via the Store API OAuth endpoints.
#
# Additive only: creates two tables, touches no existing table or data.
# Reversible via `change`. Deleting a provider row never cascades to users
# or identities (no dependent option) — its identities simply stop
# resolving because login requires an enabled provider record.
class CreateOauthProvidersAndIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :spree_oauth_providers do |t|
      t.string :provider, null: false
      t.string :name, null: false
      t.string :client_id
      t.string :client_secret
      t.boolean :enabled, null: false, default: false
      t.integer :position, null: false, default: 0

      t.timestamps
    end
    add_index :spree_oauth_providers, :provider, unique: true

    create_table :spree_oauth_identities do |t|
      t.references :user, null: false, foreign_key: { to_table: :spree_users },
                          index: { name: :index_oauth_identities_on_user_id }
      t.string :provider, null: false
      t.string :uid, null: false
      t.string :email

      t.timestamps
    end
    add_index :spree_oauth_identities, %i[provider uid], unique: true,
              name: :index_oauth_identities_on_provider_and_uid
  end
end

# frozen_string_literal: true

class AddPermissionSetNamesToSpreeRoles < ActiveRecord::Migration[8.1]
  def change
    add_column :spree_roles, :permission_set_names, :text
  end
end

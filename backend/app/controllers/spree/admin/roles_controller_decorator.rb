# frozen_string_literal: true

module Spree
  module Admin
    module RolesControllerDecorator
      private

      def permitted_resource_params
        params.require(:role).permit(permitted_role_attributes, permission_set_names: [])
      end
    end
  end
end

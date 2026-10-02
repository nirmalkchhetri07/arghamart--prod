# frozen_string_literal: true

module Spree
  module Admin
    module AdminUsersControllerDecorator
      private

      def load_invitation
        raise ActiveRecord::RecordNotFound if params[:token].blank?

        @invitation = Spree::Invitation.pending.not_expired.find_by!(token: params[:token])
      rescue ActiveRecord::RecordNotFound
        render 'spree/admin/invitations/expired', status: :not_found
      end
    end
  end
end

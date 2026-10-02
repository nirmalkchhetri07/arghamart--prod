# frozen_string_literal: true

module Spree
  module Admin
    module AdminUsersControllerDecorator
      # Self-signup POST. Core runs save + accept! with no lock, so a mobile
      # double-tap/retry could pass the `pending` check twice and either fail
      # with a bogus "invitation expired" page or create two admin users.
      # Accept under a row lock: exactly one admin user is created and exactly
      # one invitation.accepted event is emitted.
      def create
        @admin_user = Spree.admin_user_class.new(permitted_params)
        accepted = false

        @invitation.with_lock do
          next unless invitation_open?

          @invitation.invitee = @admin_user
          if @admin_user.save && @invitation.accept!
            accepted = true
          else
            raise ActiveRecord::Rollback
          end
        end

        if accepted
          if defined?(sign_in)
            sign_in(Spree.admin_user_class.model_name.singular_route_key, @admin_user)
          end
          redirect_to spree.admin_path
        elsif @invitation.accepted?
          # Lost the race: the concurrent/repeat request accepted first.
          redirect_for_accepted_invitation
        elsif @admin_user.errors.any?
          render :new, status: :unprocessable_content
        else
          # The invitation expired between load_invitation and the lock.
          render 'spree/admin/invitations/expired', status: :not_found
        end
      end

      private

      # Unlike core (pending.not_expired.find_by!), a token whose invitation
      # was already accepted must not render the "invalid or expired" page —
      # that is the message users saw after a successful signup. Unknown,
      # deleted and still-pending-but-expired tokens keep the expired page.
      def load_invitation
        raise ActiveRecord::RecordNotFound if params[:token].blank?

        @invitation = Spree::Invitation.find_by!(token: params[:token])
        raise ActiveRecord::RecordNotFound unless invitation_open? || @invitation.accepted?

        redirect_for_accepted_invitation if @invitation.accepted?
      rescue ActiveRecord::RecordNotFound
        render 'spree/admin/invitations/expired', status: :not_found
      end

      def invitation_open?
        @invitation.pending? && @invitation.expires_at.present? && @invitation.expires_at > Time.current
      end

      def redirect_for_accepted_invitation
        if try_spree_current_user.present? && @invitation.invitee == try_spree_current_user
          redirect_to spree.admin_path
        else
          flash[:notice] = Spree.t('admin.invitations.already_accepted')
          try_to_redirect_to_login_path
        end
      end
    end
  end
end

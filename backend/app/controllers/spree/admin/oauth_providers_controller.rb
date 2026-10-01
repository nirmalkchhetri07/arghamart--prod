# frozen_string_literal: true

# Serves /admin/social-login (Social Login providers).
#
# Admins add, edit, enable/disable and remove OAuth providers without
# touching code or env vars. Client secrets are encrypted at rest and the
# edit form never renders them: a blank secret field keeps the stored one.
module Spree
  module Admin
    class OauthProvidersController < Spree::Admin::BaseController
      include Spree::Admin::SettingsConcern

      before_action :authorize_providers
      before_action :load_provider, only: %i[edit update destroy toggle]

      # GET /admin/social-login
      def index
        @providers = Spree::OauthProvider.ordered
      end

      # GET /admin/oauth_providers/new
      def new
        @provider = Spree::OauthProvider.new(enabled: true)
      end

      # POST /admin/oauth_providers
      def create
        @provider = Spree::OauthProvider.new(provider_params)

        if @provider.save
          flash[:success] = Spree.t('admin.oauth.created')
          redirect_to spree.admin_social_login_path
        else
          flash.now[:error] = @provider.errors.full_messages.to_sentence
          render :new, status: :unprocessable_content
        end
      end

      # GET /admin/oauth_providers/:id/edit
      def edit
        # @provider set by before_action.
      end

      # PATCH /admin/oauth_providers/:id
      def update
        # A blank secret means "keep the stored one" — never overwrite it
        # with an encrypted empty string.
        attrs = provider_params
        attrs.delete(:client_secret) if attrs[:client_secret].blank?

        if @provider.update(attrs)
          flash[:success] = Spree.t('admin.oauth.updated')
          redirect_to spree.admin_social_login_path
        else
          flash.now[:error] = @provider.errors.full_messages.to_sentence
          render :edit, status: :unprocessable_content
        end
      end

      # DELETE /admin/oauth_providers/:id — users and linked identities stay;
      # the provider simply stops resolving at login.
      def destroy
        @provider.destroy
        flash[:success] = Spree.t('admin.oauth.deleted')
        redirect_to spree.admin_social_login_path
      end

      # POST /admin/oauth_providers/:id/toggle — flip enabled on/off.
      def toggle
        @provider.update!(enabled: !@provider.enabled?)
        flash[:success] = Spree.t(@provider.enabled? ? 'admin.oauth.enabled' : 'admin.oauth.disabled')
        redirect_to spree.admin_social_login_path
      end

      private

      def authorize_providers
        authorize! :manage, Spree::OauthProvider
      end

      def load_provider
        @provider = Spree::OauthProvider.find(params[:id])
      end

      def provider_params
        params.require(:oauth_provider).permit(
          :provider, :name, :client_id, :client_secret, :enabled, :position
        )
      end
    end
  end
end

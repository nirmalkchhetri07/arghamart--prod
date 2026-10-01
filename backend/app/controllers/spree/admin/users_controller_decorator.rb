# frozen_string_literal: true

# Phone is required when staff create a customer in /admin (phone numbers
# identify customers more reliably than email in Nepal). Email is optional
# instead and stays blank when omitted (see Spree::User#email_required?).
# Both are scoped to admin creation only: model-level phone changes would
# also affect storefront self-registrations, which don't collect a phone
# number. Editing stays fully optional so legacy accounts remain editable.
module Spree
  module Admin
    module UsersControllerDecorator
      def create
        if params[:user].present?
          params[:user][:phone] = params[:user][:phone].to_s.strip

          if params[:user][:phone].blank?
            @user = Spree.user_class.new(user_params)
            @user.password ||= SecureRandom.hex(16)
            @user.password_confirmation ||= @user.password
            @user.errors.add(:phone, :blank)
            render :new, status: :unprocessable_content and return
          end
        end

        super
      end

      # Prefills the New User form from query params (used by the New Order
      # phone lookup redirect: ?user[phone]=…&user[email]=…).
      def new
        super
        @user ||= Spree.user_class.new
        @user.phone = params.dig(:user, :phone) if params.dig(:user, :phone).present?
        @user.email = params.dig(:user, :email) if params.dig(:user, :email).present?
      end
    end

    UsersController.prepend UsersControllerDecorator
  end
end

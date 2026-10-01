# frozen_string_literal: true

# Guards against blank-email customers (phone-identified accounts, see
# Spree::User#email_required?): user association must never wipe an order's
# email with a blank one — e.g. admin creates an order with a typed guest
# email, then the phone lookup links a customer without an email address.
module Spree
  module OrderDecorator
    # rubocop:disable Style/OptionalBooleanParameter -- mirrors Spree::Order#associate_user! signature for super
    def associate_user!(user, override_email = true)
      super(user, override_email && user.email.present?)
    end
    # rubocop:enable Style/OptionalBooleanParameter

    private

    def link_by_email
      self.email = user.email if user&.email.present?
    end
  end

  Order.prepend OrderDecorator
end

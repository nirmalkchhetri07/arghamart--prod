class Spree::User < Spree.base_class
  include Spree::UserAddress
  include Spree::UserMethods
  include Spree::UserPaymentSource

  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # Phone is the primary customer identifier in Nepal, so email is optional:
  # admin-created accounts may leave it blank (see UsersControllerDecorator).
  # Devise's :validatable still checks format/uniqueness whenever an email IS
  # given. Blank is normalized to nil so blank accounts never collide.
  before_validation :nullify_blank_email

  def email_required?
    false
  end

  private

  def nullify_blank_email
    self.email = nil if email.blank?
  end
end

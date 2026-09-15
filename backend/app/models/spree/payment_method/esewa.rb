# app/models/spree/payment_method/esewa.rb
module Spree
  class PaymentMethod::Esewa < Spree::PaymentMethod
    preference :product_code, :string     # merchant/product code from eSewa
    preference :secret_key, :string
    preference :env, :string, default: 'sandbox' # sandbox | production

    def payment_icon_name = 'esewa'
    def session_required? = true
    def source_required? = false
    def payment_session_class = Spree::PaymentSessions::Esewa
  end
end
# frozen_string_literal: true

module Webhooks
  class NcmController < ActionController::API
    def create
      partner = Spree::DeliveryPartner.find_by(provider: 'ncm')
      return head :unauthorized unless partner && valid_secret?(partner)

      JSON.parse(request.raw_post.presence || '{}')

      head :ok
    rescue JSON::ParserError
      head :bad_request
    end

    private

    def valid_secret?(partner)
      expected = partner.webhook_secret.to_s
      supplied = params[:secret].to_s
      expected.bytesize == supplied.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(expected, supplied)
    end
  end
end
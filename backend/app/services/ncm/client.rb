# frozen_string_literal: true

require 'net/http'

module Ncm
  # Node equivalent: typed HTTP client/service for the NCM REST API.
  class Client
    BASE_URLS = {
      'sandbox' => 'https://demo.nepalcanmove.com',
      # NCM documentation supplied for this integration documents the demo
      # host only. Set the production host explicitly before using production.
      'production' => ENV['NCM_PRODUCTION_BASE_URL']
    }.freeze

    PATHS = {
      branches: '/api/v2/branches',
      shipping_rate: '/api/v1/shipping-rate',
      order_detail: '/api/v1/order',
      order_comments: '/api/v1/order/comment',
      order_status: '/api/v1/order/status',
      bulk_comments: '/api/v1/order/getbulkcomments',
      create_order: '/api/v1/order/create',
      add_comment: '/api/v1/comment',
      bulk_statuses: '/api/v1/orders/statuses'
    }.freeze

    class Error < StandardError
      attr_reader :response

      def initialize(message, response: nil)
        @response = response
        super(message)
      end
    end

    class AuthenticationError < Error; end
    class ValidationError < Error; end
    class NotFoundError < Error; end
    class UnexpectedResponseError < Error; end
    class ConfigurationError < Error; end
    class NetworkError < Error; end

    def initialize(environment:, api_token:)
      @base_url = BASE_URLS.fetch(environment) do
        raise ConfigurationError, "Unsupported NCM environment: #{environment}"
      end
      raise ConfigurationError, 'NCM production base URL is not configured' if @base_url.blank?
      raise ConfigurationError, 'NCM API token is not configured' if api_token.blank?

      @api_token = api_token
    end

    def branches
      get(PATHS.fetch(:branches))
    end

    def rate(creation:, destination:, type:)
      get(PATHS.fetch(:shipping_rate), params: { creation:, destination:, type: })
    end

    def order_detail(order_id)
      get(PATHS.fetch(:order_detail), params: { id: order_id })
    end

    def order_comments(order_id)
      get(PATHS.fetch(:order_comments), params: { id: order_id })
    end

    def order_status_history(order_id)
      get(PATHS.fetch(:order_status), params: { id: order_id })
    end

    def last_25_comments
      get(PATHS.fetch(:bulk_comments))
    end

    def bulk_statuses(order_ids)
      post(PATHS.fetch(:bulk_statuses), body: { orders: order_ids }, retry_network: true)
    end

    def create_order(payload)
      post(PATHS.fetch(:create_order), body: payload, retry_network: false)
    end

    def add_comment(order_id:, comments:)
      post(PATHS.fetch(:add_comment), body: { orderid: order_id, comments: comments }, retry_network: true)
    end

    private

    def get(path, params: {})
      request(Net::HTTP::Get, path, params:, retry_network: true)
    end

    def post(path, body:, retry_network:)
      request(Net::HTTP::Post, path, body:, retry_network:)
    end

    def request(http_class, path, params: {}, body: nil, retry_network:)
      uri = URI.join(@base_url, path)
      uri.query = URI.encode_www_form(params) if params.present?
      request = http_class.new(uri)
      request['Authorization'] = "Token #{@api_token}"
      request['Content-Type'] = 'application/json' if body
      request.body = JSON.generate(body) if body

      response = perform(request, retry_network:)
      parse_response(response)
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNRESET => e
      raise NetworkError, "NCM request failed: #{e.class}"
    end

    def perform(request, retry_network:)
      attempts = retry_network ? 2 : 1
      attempts.times do |attempt|
        return Net::HTTP.start(request.uri.hostname, request.uri.port,
                               use_ssl: request.uri.scheme == 'https',
                               open_timeout: 5, read_timeout: 10) { |http| http.request(request) }
      rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNRESET
        raise if attempt == attempts - 1
      end
    end

    def parse_response(response)
      body = response.body.presence ? JSON.parse(response.body) : {}
      return body if response.is_a?(Net::HTTPSuccess)

      error_class = case response.code.to_i
                    when 401 then AuthenticationError
                    when 400 then ValidationError
                    when 404 then NotFoundError
                    else UnexpectedResponseError
                    end
      raise error_class.new("NCM API returned HTTP #{response.code}", response: response)
    rescue JSON::ParserError
      raise UnexpectedResponseError.new('NCM API returned invalid JSON', response: response)
    end
  end
end
# frozen_string_literal: true
require 'common/client/configuration'
require 'singleton'

module SM
  class Configuration < Common::Client::Configuration
    include Singleton

    def app_token
      ENV['MHV_SM_APP_TOKEN']
    end

    def base_path
      "#{ENV['MHV_SM_HOST']}/mhv-sm-api/patient/v1/"
    end

    def breakers_service
      return @service if defined?(@service)

      path = URI.parse(base_path).path
      host = URI.parse(base_path).host
      matcher = proc do |request_env|
        request_env.url.host == host && request_env.url.path =~ /^#{path}/
      end

      @service = Breakers::Service.new(
        name: 'SM',
        request_matcher: matcher
      )
    end

    def connection
      Faraday.new(base_path, headers: base_request_headers, request: request_options) do |conn|
        conn.use :breakers
        conn.request :camelcase
        conn.request :multipart_request
        conn.request :multipart
        conn.request :json
        # Uncomment this out for generating curl output to send to MHV dev and test only
        # conn.request :curl, ::Logger.new(STDOUT), :warn

        # conn.response :logger, ::Logger.new(STDOUT), bodies: true
        conn.response :sm_parser
        conn.response :snakecase
        conn.response :raise_error
        conn.response :json_parser

        conn.adapter Faraday.default_adapter
      end
    end
  end
end

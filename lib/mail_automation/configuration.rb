# frozen_string_literal: true

require 'common/client/configuration/rest'
require 'common/client/middleware/response/raise_error'

module MailAutomation
  class Configuration < Common::Client::Configuration::REST
    def base_path
      Settings.mail_automation.url
    end

    def service_name
      'MasNotificationClient'
    end

    def connection
      Faraday.new(base_path, headers: base_request_headers, request: request_options) do |faraday|
        faraday.use :breakers
        faraday.use Faraday::Response::RaiseError

        # Uncomment this if you want curl command equivalent or response output to log
        # faraday.request(:curl, ::Logger.new(STDOUT), :warn) unless Rails.env.production?
        # faraday.response(:logger, ::Logger.new(STDOUT), bodies: true) unless Rails.env.production?

        faraday.response :json
        faraday.adapter Faraday.default_adapter
      end
    end
  end
end
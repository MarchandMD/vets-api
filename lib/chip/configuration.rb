# frozen_string_literal: true

module Chip
  class Configuration < Common::Client::Configuration::REST
    def server_url
      "#{Settings.chip.url}/#{Settings.chip.base_path}"
    end

    def api_gtwy_id
      Settings.chip.api_gtwy_id
    end

    def service_name
      'Chip'
    end

    def valid_tenant?(tenant_name:, tenant_id:)
      Settings.chip[tenant_name]&.tenant_id == tenant_id
    end

    def connection
      Faraday.new(url: server_url) do |conn|
        conn.use :breakers
        conn.response :raise_error, error_prefix: service_name
        conn.response :betamocks if Settings.chip.mock?

        conn.adapter Faraday.default_adapter
      end
    end
  end
end

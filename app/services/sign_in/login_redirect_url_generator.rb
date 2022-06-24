# frozen_string_literal: true

module SignIn
  class LoginRedirectUrlGenerator
    attr_reader :client_id, :login_code, :client_state, :type

    def initialize(user_code_map:)
      @login_code = user_code_map.login_code
      @type = user_code_map.type
      @client_id = user_code_map.client_id
      @client_state = user_code_map.client_state
    end

    def perform
      redirect_uri = get_client_id_mapped_redirect_uri
      redirect_uri_params = get_redirect_uri_params
      redirect_uri.query = redirect_uri_params.to_query
      redirect_uri.to_s
    end

    private

    def get_client_id_mapped_redirect_uri
      case client_id
      when 'mobile'
        URI.parse(Settings.sign_in.redirect_uri)
      when 'web'
        URI.parse(Settings.sign_in.web_redirect_uri)
      else
        raise Errors::InvalidClientIdError, 'Client id is not valid'
      end
    end

    def get_redirect_uri_params
      params = {}
      params[:code] = login_code
      params[:type] = type
      params[:state] = client_state if client_state.present?
      params
    end
  end
end
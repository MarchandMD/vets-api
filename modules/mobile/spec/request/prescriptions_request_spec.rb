# frozen_string_literal: true

require 'rails_helper'
require 'support/rx_client_helpers'
require 'support/shared_examples_for_mhv'
require_relative '../support/iam_session_helper'
require_relative '../support/matchers/json_schema_matcher'

RSpec.describe 'health/rx/prescriptions', type: :request do
  include JsonSchemaMatchers
  include Rx::ClientHelpers

  let(:mhv_account_type) { 'Premium' }
  let(:json_body_headers) { { 'Content-Type' => 'application/json', 'Accept' => 'application/json' } }

  before(:all) do
    @original_cassette_dir = VCR.configure(&:cassette_library_dir)
    VCR.configure { |c| c.cassette_library_dir = 'modules/mobile/spec/support/vcr_cassettes' }
  end

  after(:all) { VCR.configure { |c| c.cassette_library_dir = @original_cassette_dir } }

  before do
    allow_any_instance_of(MHVAccountTypeService).to receive(:mhv_account_type).and_return(mhv_account_type)
    allow(Rx::Client).to receive(:new).and_return(authenticated_client)
    current_user = build(:iam_user, :mhv)

    iam_sign_in(current_user)
  end

  describe 'GET /mobile/v0/health/rx/prescriptions', :aggregate_failures do
    context 'with a valid EVSS response and no failed facilities' do
      it 'returns 200' do
        VCR.use_cassette('rx_refill/prescriptions/gets_a_list_of_all_prescriptions') do
          get '/mobile/v0/health/rx/prescriptions', headers: iam_headers
        end
        expect(response).to have_http_status(:ok)
        expect(response.body).to match_json_schema('prescription')
      end
    end

    context 'with a valid EVSS response and failed facilities' do
      it 'returns 200 and omits failed facilities' do
        VCR.use_cassette('rx_refill/prescriptions/handles_failed_stations') do
          get '/mobile/v0/health/rx/prescriptions', headers: iam_headers
        end
        expect(response).to have_http_status(:ok)
        expect(response.body).to match_json_schema('prescription')
      end
    end

    context 'when user does not have mhv access' do
      it 'returns a 403 forbidden response' do
        unauthorized_user = build(:iam_user)
        iam_sign_in(unauthorized_user)

        VCR.use_cassette('rx_refill/prescriptions/gets_a_list_of_all_prescriptions') do
          get '/mobile/v0/health/rx/prescriptions', headers: iam_headers
        end
        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body).to eq({ 'errors' =>
                                               [{ 'title' => 'Forbidden',
                                                  'detail' => 'User does not have access to the requested resource',
                                                  'code' => '403',
                                                  'status' => '403' }] })
      end
    end

    describe 'pagination parameters' do
      it 'forms meta links' do
        params = { page: { number: 2, size: 3 } }

        VCR.use_cassette('rx_refill/prescriptions/gets_a_list_of_all_prescriptions') do
          get '/mobile/v0/health/rx/prescriptions', params: params, headers: iam_headers
        end
        expect(response).to have_http_status(:ok)
        expect(response.body).to match_json_schema('prescription')
        expect(response.parsed_body['meta']).to eq({ 'pagination' =>
                                                      { 'currentPage' => 2,
                                                        'perPage' => 3,
                                                        'totalPages' => 5,
                                                        'totalEntries' => 14 } })
        expect(response.parsed_body['links']).to eq(
          { 'self' =>
            'http://www.example.com/mobile/v0/health/rx/prescriptions?page[size]=3&page[number]=2',
            'first' =>
            'http://www.example.com/mobile/v0/health/rx/prescriptions?page[size]=3&page[number]=1',
            'prev' =>
            'http://www.example.com/mobile/v0/health/rx/prescriptions?page[size]=3&page[number]=1',
            'next' =>
            'http://www.example.com/mobile/v0/health/rx/prescriptions?page[size]=3&page[number]=3',
            'last' =>
            'http://www.example.com/mobile/v0/health/rx/prescriptions?page[size]=3&page[number]=5' }
        )
      end
    end

    describe 'filtering parameters' do
      context 'filter by refill status' do
        let(:filter_param) { 'filter[[refill_status][eq]]=refillinprocess' }

        it 'returns all prescriptions that are refillinprocess status' do
          VCR.use_cassette('rx_refill/prescriptions/gets_a_list_of_all_prescriptions') do
            get "/mobile/v0/health/rx/prescriptions?#{filter_param}", headers: iam_headers
          end
          expect(response).to have_http_status(:ok)
          expect(response.body).to match_json_schema('prescription')

          refill_statuses = response.parsed_body['data'].map { |d| d.dig('attributes', 'refillStatus') }.uniq
          expect(refill_statuses).to eq(['refillinprocess'])
        end
      end

      context 'filter by not equal to refill status' do
        let(:filter_param) { 'filter[[refill_status][not_eq]]=refillinprocess' }

        it 'returns all prescriptions that are not refillinprocess status' do
          VCR.use_cassette('rx_refill/prescriptions/gets_a_list_of_all_prescriptions') do
            get "/mobile/v0/health/rx/prescriptions?#{filter_param}", headers: iam_headers
          end
          expect(response).to have_http_status(:ok)
          expect(response.body).to match_json_schema('prescription')

          refill_statuses = response.parsed_body['data'].map { |d| d.dig('attributes', 'refillStatus') }.uniq

          # does not include refillinprocess
          expect(refill_statuses).to eq(%w[expired discontinued hold active submitted])
        end
      end

      context 'invalid filter option' do
        let(:filter_param) { 'filter[[quantity][eq]]=8' }

        it 'cannot filter by unexpected field' do
          VCR.use_cassette('rx_refill/prescriptions/gets_a_list_of_all_prescriptions') do
            get "/mobile/v0/health/rx/prescriptions?#{filter_param}", headers: iam_headers
          end
          expect(response).to have_http_status(:bad_request)
          expect(response.parsed_body).to eq({ 'errors' =>
                                                [{ 'title' => 'Filter not allowed',
                                                   'detail' =>
                                                    '"{"quantity"=>{"eq"=>"8"}}" is not allowed for filtering',
                                                   'code' => '104',
                                                   'status' => '400' }] })
        end
      end
    end

    describe 'sorting parameters' do
      context 'sorts by ASC refill status' do
        let(:params) { { sort: 'refill_status' } }

        it 'sorts prescriptions by ASC refill_status' do
          VCR.use_cassette('rx_refill/prescriptions/gets_a_list_of_all_prescriptions') do
            get '/mobile/v0/health/rx/prescriptions', params: params, headers: iam_headers
          end

          expect(response).to have_http_status(:ok)
          expect(response.body).to match_json_schema('prescription')
          expect(response.parsed_body['data'].map { |d| d.dig('attributes', 'refillStatus') }).to eq(
            %w[active
               discontinued
               discontinued
               expired
               expired
               hold
               refillinprocess
               refillinprocess
               refillinprocess
               refillinprocess]
          )
        end
      end

      context 'sorts by DESC refill status' do
        let(:params) { { sort: '-refill_status' } }

        it 'sorts prescriptions by DESC refill_status' do
          VCR.use_cassette('rx_refill/prescriptions/gets_a_list_of_all_prescriptions') do
            get '/mobile/v0/health/rx/prescriptions', params: params, headers: iam_headers
          end

          expect(response).to have_http_status(:ok)
          expect(response.body).to match_json_schema('prescription')
          expect(response.parsed_body['data'].map do |d|
                   d.dig('attributes',
                         'refillStatus')
                 end).to eq(%w[submitted refillinprocess refillinprocess refillinprocess refillinprocess refillinprocess
                               refillinprocess refillinprocess hold expired])
        end
      end

      context 'invalid sort option' do
        let(:params) { { sort: 'quantity' } }

        it 'sorts prescriptions by refill_status' do
          VCR.use_cassette('rx_refill/prescriptions/gets_a_list_of_all_prescriptions') do
            get '/mobile/v0/health/rx/prescriptions', params: params, headers: iam_headers
          end

          expect(response).to have_http_status(:bad_request)
          expect(response.parsed_body).to eq({ 'errors' =>
                                                [{ 'title' => 'Invalid sort criteria',
                                                   'detail' =>
                                                    '"quantity" is not a valid sort criteria for "Prescription"',
                                                   'code' => '106',
                                                   'status' => '400' }] })
        end
      end
    end

    describe 'all parameters' do
      it 'Filters, sorts and paginates prescriptions' do
        params = { 'page' => { number: 2, size: 3 }, 'sort' => '-refill_date' }

        # nested array causes issues as query param, so setting it in url
        filter_param = 'filter[[refill_status][eq]]=refillinprocess'

        VCR.use_cassette('rx_refill/prescriptions/gets_a_list_of_all_prescriptions') do
          get "/mobile/v0/health/rx/prescriptions?#{filter_param}", params: params, headers: iam_headers
        end
        expect(response).to have_http_status(:ok)
        expect(response.body).to match_json_schema('prescription')
        expect(response.parsed_body['meta']).to eq({ 'pagination' =>
                                                       { 'currentPage' => 2,
                                                         'perPage' => 3,
                                                         'totalPages' => 3,
                                                         'totalEntries' => 7 } })
        expect(response.parsed_body['links']).to eq(
          {
            'self' =>
              'http://www.example.com/mobile/v0/health/rx/prescriptions?page[size]=3&page[number]=2&filter[[refill_status][eq]]=refillinprocess&sort=-refill_date',
            'first' =>
              'http://www.example.com/mobile/v0/health/rx/prescriptions?page[size]=3&page[number]=1&filter[[refill_status][eq]]=refillinprocess&sort=-refill_date',
            'prev' =>
              'http://www.example.com/mobile/v0/health/rx/prescriptions?page[size]=3&page[number]=1&filter[[refill_status][eq]]=refillinprocess&sort=-refill_date',
            'next' =>
              'http://www.example.com/mobile/v0/health/rx/prescriptions?page[size]=3&page[number]=3&filter[[refill_status][eq]]=refillinprocess&sort=-refill_date',
            'last' =>
              'http://www.example.com/mobile/v0/health/rx/prescriptions?page[size]=3&page[number]=3&filter[[refill_status][eq]]=refillinprocess&sort=-refill_date'
          }
        )

        statuses = response.parsed_body['data'].map { |d| d.dig('attributes', 'refillStatus') }.uniq
        expect(statuses).to eq(['refillinprocess'])

        expect(response.parsed_body['data'].map { |p| p.dig('attributes', 'refillDate') }).to eq(
          %w[
            2017-01-25T05:00:00.000Z 2016-11-30T05:00:00.000Z 2016-11-30T05:00:00.000Z
          ]
        )
      end
    end
  end
end
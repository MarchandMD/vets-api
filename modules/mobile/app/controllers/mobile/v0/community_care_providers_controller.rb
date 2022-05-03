# frozen_string_literal: true

module Mobile
  module V0
    class CommunityCareProvidersController < ApplicationController
      DEFAULT_PAGE_NUMBER = 1
      DEFAULT_PAGE_SIZE = 10
      RADIUS_MILES = 60 # value used in web app
      SERVICE_TYPES = {
        primaryCare: %w[207QA0505X 363LP2300X 363LA2200X 261QP2300X],
        foodAndNutrition: %w[133V00000X 133VN1201X 133N00000X 133NN1002X],
        podiatry: %w[213E00000X 213EG0000X 213EP1101X 213ES0131X 213ES0103X],
        optometry: %w[152W00000X 152WC0802X],
        audiologyRoutineExam: %w[231H00000X 237600000X 261QH0700X],
        audiologyHearingAidSupport: %w[231H00000X 237600000X]
      }.with_indifferent_access.freeze

      def index
        community_care_providers = ppms_api.facility_service_locator(locator_params)
        page_records, page_meta_data = paginate(community_care_providers)
        serialized = Mobile::V0::CommunityCareProviderSerializer.new(page_records, page_meta_data)
        render json: serialized, status: :ok
      end

      private

      def ppms_api
        FacilitiesApi::V1::PPMS::Client.new
      end

      def locator_params
        specialty_codes = SERVICE_TYPES[params[:serviceType]]
        raise Common::Exceptions::InvalidFieldValue.new('serviceType', params[:serviceType]) if specialty_codes.nil?

        lat, long = coordinates
        {
          latitude: lat,
          longitude: long,
          page: pagination_params[:page_number],
          per_page: pagination_params[:page_size],
          radius: RADIUS_MILES,
          specialties: specialty_codes
        }
      end

      def coordinates
        return facility_coordinates if params[:facilityId]

        user_address_coordinates
      end

      def facility_coordinates
        facility = Mobile::FacilitiesHelper.get_facilities(Array(params[:facilityId])).first
        raise Common::Exceptions::RecordNotFound, params[:facilityId] unless facility

        [facility.lat, facility.long]
      end

      def user_address_coordinates
        address = current_user.vet360_contact_info.residential_address
        unless address&.latitude && address&.longitude
          raise Common::Exceptions::UnprocessableEntity.new(
            detail: 'User has no home latitude and longitude', source: self.class.to_s
          )
        end

        [address.latitude, address.longitude]
      end

      def pagination_params
        @pagination_params ||= Mobile::V0::Contracts::GetPaginatedList.new.call(
          page_number: params.dig(:page, :number) || DEFAULT_PAGE_NUMBER,
          page_size: params.dig(:page, :size) || DEFAULT_PAGE_SIZE
        )
      end

      def paginate(records)
        url = request.base_url + request.path
        page_records, page_meta_data = Mobile::PaginationHelper.paginate(
          list: records, validated_params: pagination_params, url: url
        )
        # this is temporary. this has come up multiple times and we should develop a better solution
        page_meta_data[:links].transform_values! do |link|
          next if link.nil?

          link += "&serviceType=#{params[:serviceType]}"
          link += "&facilityId=#{params[:facilityId]}" if params[:facilityId]
          link
        end

        [page_records, page_meta_data]
      end
    end
  end
end
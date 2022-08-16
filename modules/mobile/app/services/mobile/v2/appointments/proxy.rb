# frozen_string_literal: true

require 'lighthouse/facilities/client'

module Mobile
  module V2
    module Appointments
      class Proxy
        def initialize(user)
          @user = user
        end

        def get_appointments(start_date:, end_date:, pagination_params:)
          response = vaos_v2_appointments_service.get_appointments(start_date, end_date, nil, pagination_params)
          response[:data].each do |appt|
            appt[:location_id] = Mobile::V0::Appointment.convert_non_prod_id!(appt[:location_id])
          end
          appointments = merge_clinics(response[:data])
          appointments = merge_facilities(appointments)

          appointments = vaos_v2_to_v0_appointment_adapter.parse(appointments)

          appointments.sort_by(&:start_date_utc)
        end

        private

        def merge_clinics(appointments)
          cached_clinics = {}
          appointments.each do |appt|
            clinic_id = appt[:clinic]
            next unless clinic_id

            cached = cached_clinics[clinic_id]
            cached_clinics[clinic_id] = get_clinic(appt[:location_id], clinic_id) unless cached

            service_name = cached_clinics.dig(clinic_id, :service_name)
            appt[:service_name] = service_name if service_name

            physical_location = cached_clinics.dig(clinic_id, :physical_location)
            appt[:physical_location] = physical_location if physical_location
          end
        end

        def merge_facilities(appointments)
          cached_facilities = {}
          appointments.each do |appt|
            facility_id = appt[:location_id]
            next unless facility_id

            cached = cached_facilities[facility_id]
            cached_facilities[facility_id] = get_facility(facility_id) unless cached
            appt[:location] = cached_facilities[facility_id] if cached_facilities[facility_id]
          end
        end

        def get_clinic(location_id, clinic_id)
          clinics = v2_systems_service.get_facility_clinics(location_id: location_id, clinic_ids: clinic_id)
          clinics.first unless clinics.empty?
        rescue Common::Exceptions::BackendServiceException
          Rails.logger.error(
            "Error fetching clinic #{clinic_id} for location #{location_id}",
            clinic_id: clinic_id,
            location_id: location_id
          )
          nil
        end

        def get_facility(location_id)
          vaos_mobile_facility_service.get_facility(location_id)
        rescue Common::Exceptions::BackendServiceException
          Rails.logger.error(
            "Error fetching facility details for location_id #{location_id}",
            location_id: location_id
          )
          nil
        end

        def vaos_mobile_facility_service
          VAOS::V2::MobileFacilityService.new(@user)
        end

        def vaos_v2_appointments_service
          VAOS::V2::AppointmentsService.new(@user)
        end

        def vaos_v2_to_v0_appointment_adapter
          Mobile::V0::Adapters::VAOSV2Appointments.new
        end

        def v2_systems_service
          VAOS::V2::SystemsService.new(@user)
        end
      end
    end
  end
end
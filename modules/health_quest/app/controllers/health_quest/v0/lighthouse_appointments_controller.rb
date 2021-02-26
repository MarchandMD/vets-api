# frozen_string_literal: true

module HealthQuest
  module V0
    class LighthouseAppointmentsController < HealthQuest::V0::BaseController
      def index
        render json: factory.search(request.query_parameters).response[:body]
      end

      def show
        render json: {}
      end

      private

      def appointment_params
        params.permit(:id)
      end

      def factory
        @factory =
          HealthQuest::HealthApi::Appointment::Factory.manufacture(current_user)
      end
    end
  end
end

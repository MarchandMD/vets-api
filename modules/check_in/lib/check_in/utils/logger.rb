# frozen_string_literal: true

module CheckIn
  module Utils
    class Logger
      API_STATUS_REGEXP = /\W+status\W+([^"|^,|^\\]*)/.freeze

      attr_reader :ctrl

      def self.build(controller)
        new(controller)
      end

      def initialize(controller)
        @ctrl = controller
      end

      def before
        common.merge({ filter: :before_action })
      end

      def after
        common.merge({ api_status: api_status, filter: :after_action })
      end

      def common
        {
          workflow: workflow,
          uuid: uuid,
          controller: ctrl_name,
          action: ctrl_action
        }
      end

      def ctrl_name
        ctrl.controller_name
      end

      def ctrl_action
        ctrl.action_name
      end

      def api_status
        body = ctrl.response.body

        return 'none' if body.blank?

        body.match(API_STATUS_REGEXP) { |g| g[1] if g }
      end

      def workflow
        case ctrl.controller_name
        when 'sessions' then 'Min-Auth'
        when 'pre_check_ins' then 'Pre-Check-In'
        when 'patient_check_ins' then 'Day-Of-Check-In'
        else
          ''
        end
      end

      def uuid
        ctrl.params[:id] || ctrl.permitted_params[:uuid]
      end
    end
  end
end
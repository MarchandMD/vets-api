# frozen_string_literal: true

require 'va_notify/in_progress_form_helper'

module VANotify
  class InProgressFormReminder
    include Sidekiq::Worker
    include SentryLogging
    sidekiq_options retry: 14

    class MissingICN < StandardError; end

    def perform(form_id)
      return unless enabled?

      @in_progress_form = InProgressForm.find(form_id)
      @veteran = VANotify::InProgressFormHelper.veteran_data(in_progress_form)

      raise MissingICN, "ICN not found for InProgressForm: #{in_progress_form.id}" if veteran.mpi_icn.blank?

      if only_one_supported_in_progress_form?
        template_id = VANotify::InProgressFormHelper::TEMPLATE_ID.fetch(in_progress_form.form_id)
        IcnJob.perform_async(veteran.mpi_icn, template_id, personalisation_details_single)
      elsif oldest_in_progress_form?
        template_id = Settings.vanotify.services.va_gov.template_id.in_progress_reminder_email_generic
        IcnJob.perform_async(veteran.mpi_icn, template_id, personalisation_details_multiple)
      end
    end

    private

    attr_accessor :in_progress_form, :veteran

    def enabled?
      Flipper.enabled?(:in_progress_form_reminder)
    end

    def only_one_supported_in_progress_form?
      InProgressForm.where(user_uuid: in_progress_form.user_uuid,
                           form_id: FindInProgressForms::RELEVANT_FORMS).count == 1
    end

    def oldest_in_progress_form?
      other_updated_at = InProgressForm.where(user_uuid: in_progress_form.user_uuid,
                                              form_id: FindInProgressForms::RELEVANT_FORMS).pluck(:updated_at)
      other_updated_at.all? { |date| in_progress_form.updated_at <= date }
    end

    def personalisation_details_single
      {
        'first_name' => veteran.first_name.upcase,
        'date' => in_progress_form.expires_at.strftime('%B %d, %Y')
      }
    end

    def personalisation_details_multiple
      in_progress_forms = InProgressForm.where(form_id: FindInProgressForms::RELEVANT_FORMS,
                                               user_uuid: in_progress_form.user_uuid).order(:expires_at)
      personalisation = in_progress_forms.flat_map.with_index(1) do |form, i|
        friendly_form_name = VANotify::InProgressFormHelper::FRIENDLY_FORM_SUMMARY.fetch(form.form_id)
        [
          ["form_#{i}_number", "FORM #{form.form_id}"],
          ["form_#{i}_name", "__ #{friendly_form_name} __"],
          ["form_#{i}_date", "_Application expires on: #{form.expires_at.strftime('%B %d, %Y')}_"],
          ["form_#{i}_divider", '---']
        ]
      end.to_h
      personalisation['first_name'] = veteran.first_name.upcase
      personalisation
    end
  end
end
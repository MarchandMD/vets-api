# frozen_string_literal: true

require 'lighthouse/veterans_health/client'

module RapidReadyForDecision
  class AsthmaProcessor < RrdProcessor
    def assess_data
      assessed_data = query_and_assess_lighthouse

      return if assessed_data[:medications].blank?

      assessed_data
    end

    private

    def query_and_assess_lighthouse
      client = lighthouse_client
      medications = assess_medications(client.list_resource('medication_requests'))
      { medications: medications }
    end

    ASTHMA_KEYWORDS = RapidReadyForDecision::Constants::DISABILITIES[:asthma][:keywords]

    def assess_medications(medications)
      return [] if medications.blank?

      transformed_medications = RapidReadyForDecision::LighthouseMedicationRequestData.new(medications).transform
      flagged_medications = transformed_medications.map do |medication|
        {
          **medication,
          flagged: ASTHMA_KEYWORDS.any? { |keyword| medication.to_s.downcase.include?(keyword) }
        }
      end
      flagged_medications.sort_by { |medication| medication[:flagged] ? 0 : 1 }
    end

    def med_stats_hash(assessed_data)
      { medications_count: assessed_data[:medications]&.size }
    end

    def generate_pdf(assessed_data)
      RapidReadyForDecision::FastTrackPdfGenerator.new(patient_info,
                                                       assessed_data,
                                                       :asthma).generate
    end
  end
end
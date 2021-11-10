# frozen_string_literal: true

class KmsRecordRotationJob
  include Sidekiq::Worker

  def perform(models = ApplicationRecord.descendants_using_encryption.map(&:name))
    HealthQuest::QuestionnaireResponse.skip_callback :save, :before, :set_user_demographics, raise: false do
      models.map(&:constantize).each do |m|
        Rails.logger.debug "Re-encrypting #{m.where(encrypted_kms_key: nil).count} #{m} records."
        Lockbox.rotate m.where(encrypted_kms_key: nil), attributes: m.lockbox_attributes.keys
      end
    end
  end
end

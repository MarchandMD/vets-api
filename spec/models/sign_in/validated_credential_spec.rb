# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignIn::ValidatedCredential, type: :model do
  let(:validated_credential) do
    create(:validated_credential, user_verification: user_verification, credential_email: credential_email)
  end

  let(:user_verification) { create(:user_verification) }
  let(:credential_email) { 'some-credential-email' }

  describe 'validations' do
    describe '#user_verification' do
      subject { validated_credential.user_verification }

      context 'when user_verification is nil' do
        let(:user_verification) { nil }
        let(:expected_error_message) { "Validation failed: User verification can't be blank" }
        let(:expected_error) { ActiveModel::ValidationError }

        it 'raises validation error' do
          expect { subject }.to raise_error(expected_error, expected_error_message)
        end
      end
    end
  end
end
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserAccount, type: :model do
  let(:user_account) { create(:user_account, icn: icn) }
  let(:icn) { nil }

  describe 'validations' do
    describe '#icn' do
      subject { user_account.icn }

      context 'when icn is nil' do
        let(:icn) { nil }

        it 'returns nil' do
          expect(subject).to eq(nil)
        end
      end

      context 'when icn is unique' do
        let(:icn) { 'kitty-icn' }

        it 'returns given icn value' do
          expect(subject).to eq(icn)
        end
      end

      context 'when icn is not unique' do
        let(:icn) { 'kitty-icn' }
        let(:expected_error_message) { 'Validation failed: Icn has already been taken' }

        before do
          create(:user_account, icn: icn)
        end

        it 'raises a validation error' do
          expect { subject }.to raise_error(ActiveRecord::RecordInvalid, expected_error_message)
        end
      end
    end
  end
end
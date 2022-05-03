# frozen_string_literal: true

require 'rails_helper'
require 'sidekiq/testing'

RSpec.describe RapidReadyForDecision::RrdProcessor do
  let(:rrd_processor) { described_class.new(submission) }
  let(:submission) { create(:form526_submission, :asthma_claim_for_increase) }

  describe '#add_medical_stats' do
    subject { rrd_processor.add_medical_stats(assessed_data) }

    let(:assessed_data) { { somekey: 'someValue' } }

    before { expect(rrd_processor).to receive(:med_stats_hash).and_return({ newkey: 'someValue' }) }

    it 'adds to rrd_metadata.med_stats' do
      subject
      expect(rrd_processor.claim_context.metadata_hash.dig(:med_stats, :newkey)).to eq 'someValue'
    end
  end

  describe '#set_special_issue' do
    subject { rrd_processor.set_special_issue }

    it 'calls add_special_issue' do
      expect_any_instance_of(RapidReadyForDecision::RrdSpecialIssueManager).to receive(:add_special_issue)
      subject
    end
  end

  describe '#release_pdf?' do
    subject { rrd_processor.release_pdf? }

    it 'returns true when Flipper symbol does not exist' do
      Flipper.remove(:rrd_hypertension_release_pdf)
      expect(subject).to eq true
    end
  end

  context 'when run in a Sidekiq job', :vcr do
    around do |example|
      VCR.use_cassette('evss/claims/claims_without_open_compensation_claims') do
        VCR.use_cassette('rrd/asthma', &example)
      end
    end

    it 'finishes successfully' do
      Sidekiq::Testing.inline! do
        RapidReadyForDecision::Form526BaseJob.perform_async(submission.id)
        submission.reload
        expect(submission.rrd_pdf_created?).to be true
        expect(submission.rrd_pdf_uploaded_to_s3?).to be true

        # when release_pdf? is true, add pdf for uploading and set special issue
        expect(Flipper.enabled?(:rrd_asthma_release_pdf)).to be true
        expect(submission.rrd_pdf_added_for_uploading?).to be true
        expect(submission.rrd_special_issue_set?).to be true
      end
    end

    context 'when the user uuid is not associated with an Account' do
      let(:submission_without_account) do
        create(:form526_submission, :asthma_claim_for_increase, user_uuid: 'inconceivable')
      end

      it 'finishes successfully' do
        Sidekiq::Testing.inline! do
          expect do
            RapidReadyForDecision::Form526BaseJob.perform_async(submission_without_account.id)
          end.not_to raise_error
        end
      end

      context 'AND the edipi auth header is blank' do
        let(:user) { FactoryBot.create(:disabilities_compensation_user, icn: '2000163') }
        let(:auth_headers) do
          EVSS::DisabilityCompensationAuthHeaders.new(user).add_headers(EVSS::AuthHeaders.new(user).to_h)
        end
        let(:submission_without_account_or_edpid) do
          auth_headers.delete('va_eauth_dodedipnid')

          create(:form526_submission, :asthma_claim_for_increase,
                 user: user,
                 user_uuid: 'nonsense',
                 auth_headers_json: auth_headers.to_json)
        end

        it 'raises an error' do
          Sidekiq::Testing.inline! do
            expect(submission_without_account_or_edpid.auth_headers['va_eauth_dodedipnid']).to be_blank

            expect do
              RapidReadyForDecision::Form526BaseJob.perform_async(submission_without_account_or_edpid.id)
            end.to raise_error RapidReadyForDecision::ClaimContext::AccountNotFoundError
          end
        end
      end
    end

    context 'when an account for the user is NOT found' do
      before do
        allow(Account).to receive(:where).and_return Account.none
        allow(Account).to receive(:find_by).and_return nil
      end

      it 'raises AccountNotFoundError exception' do
        Sidekiq::Testing.inline! do
          expect do
            RapidReadyForDecision::Form526BaseJob.perform_async(submission.id)
          end.to raise_error RapidReadyForDecision::ClaimContext::AccountNotFoundError
        end
      end
    end

    context 'when the ICN does NOT exist on the user Account' do
      before do
        allow_any_instance_of(Account).to receive(:icn).and_return('')
      end

      it 'raises an ArgumentError' do
        Sidekiq::Testing.inline! do
          expect do
            RapidReadyForDecision::Form526BaseJob.perform_async(submission.id)
          end.to raise_error(ArgumentError, 'no ICN passed in for LH API request.')
        end
      end
    end
  end
end
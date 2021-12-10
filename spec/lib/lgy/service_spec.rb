# frozen_string_literal: true

require 'rails_helper'
require 'lgy/service'

describe LGY::Service do
  subject { described_class.new(edipi: user.edipi, icn: user.icn) }

  let(:user) { FactoryBot.create(:evss_user, :loa3) }

  describe '#get_determination' do
    subject { described_class.new(edipi: user.edipi, icn: user.icn).get_determination }

    context 'when response is eligible' do
      before { VCR.insert_cassette 'lgy/determination_eligible' }

      after { VCR.eject_cassette 'lgy/determination_eligible' }

      it 'response code is a 200' do
        expect(subject.status).to eq 200
      end

      it "response body['status'] is ELIGIBLE" do
        expect(subject.body['status']).to eq 'ELIGIBLE'
      end

      it 'response body has key determination_date' do
        expect(subject.body).to have_key 'determination_date'
      end
    end
  end

  describe '#get_application' do
    context 'when application is not found' do
      it 'response code is a 404' do
        VCR.use_cassette 'lgy/application_not_found' do
          expect(subject.get_application.status).to eq 404
        end
      end
    end
  end

  describe '#coe_status' do
    context 'when get_determination is eligible and get_application is a 404' do
      it 'returns eligible' do
        VCR.use_cassette 'lgy/determination_eligible' do
          VCR.use_cassette 'lgy/application_not_found' do
            expect(subject.coe_status).to eq 'eligible'
          end
        end
      end
    end

    context 'when get_determination is Unable to Determine Automatically and get_application is a 404' do
      it 'returns unable-to-determine-eligibility' do
        VCR.use_cassette 'lgy/determination_unable_to_determine' do
          VCR.use_cassette 'lgy/application_not_found' do
            expect(subject.coe_status).to eq 'unable-to-determine-eligibility'
          end
        end
      end
    end
  end
end

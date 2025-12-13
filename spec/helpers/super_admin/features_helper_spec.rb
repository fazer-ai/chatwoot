# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SuperAdmin::FeaturesHelper do
  describe '.fazer_ai_subscription_details' do
    context 'when subscription is active' do
      before do
        allow(FazerAiHub).to receive(:subscription_status).and_return('active')
        allow(FazerAiHub).to receive(:enabled_features).and_return(%w[kanban])
      end

      it 'returns active status with green styling' do
        result = described_class.fazer_ai_subscription_details

        expect(result).to include('text-green-600')
        expect(result).to include('Active')
        expect(result).to include('Kanban')
      end
    end

    context 'when subscription is past_due' do
      before do
        allow(FazerAiHub).to receive(:subscription_status).and_return('past_due')
        allow(FazerAiHub).to receive(:enabled_features).and_return(%w[kanban])
      end

      it 'returns past due status with yellow styling' do
        result = described_class.fazer_ai_subscription_details

        expect(result).to include('text-yellow-600')
        expect(result).to include('Past Due')
      end
    end

    context 'when subscription is trialing' do
      before do
        allow(FazerAiHub).to receive(:subscription_status).and_return('trialing')
        allow(FazerAiHub).to receive(:enabled_features).and_return([])
      end

      it 'returns trialing status with blue styling' do
        result = described_class.fazer_ai_subscription_details

        expect(result).to include('text-blue-600')
        expect(result).to include('Trialing')
      end
    end

    context 'when subscription is inactive' do
      before do
        allow(FazerAiHub).to receive(:subscription_status).and_return('inactive')
        allow(FazerAiHub).to receive(:enabled_features).and_return([])
      end

      it 'returns inactive status with slate styling' do
        result = described_class.fazer_ai_subscription_details

        expect(result).to include('text-slate-500')
        expect(result).to include('Inactive')
      end
    end

    context 'when there are no enabled features' do
      before do
        allow(FazerAiHub).to receive(:subscription_status).and_return('active')
        allow(FazerAiHub).to receive(:enabled_features).and_return([])
      end

      it 'shows None for features' do
        result = described_class.fazer_ai_subscription_details

        expect(result).to include('Features:')
        expect(result).to include('None')
      end
    end

    context 'when there are multiple enabled features' do
      before do
        allow(FazerAiHub).to receive(:subscription_status).and_return('active')
        allow(FazerAiHub).to receive(:enabled_features).and_return(%w[kanban other_feature])
      end

      it 'shows all features titleized and comma separated' do
        result = described_class.fazer_ai_subscription_details

        expect(result).to include('Kanban, Other Feature')
      end
    end
  end
end

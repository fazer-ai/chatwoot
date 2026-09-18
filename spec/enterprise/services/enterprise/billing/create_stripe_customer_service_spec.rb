require 'rails_helper'

describe Enterprise::Billing::CreateStripeCustomerService do
  subject(:create_stripe_customer_service) { described_class }

  let(:account) { create(:account) }
  let!(:admin1) { create(:user, account: account, role: :administrator) }
  let(:admin2) { create(:user, account: account, role: :administrator) }
  let(:subscriptions_list) { double }
  let(:current_period_end) { 1_686_567_520 }
  let(:subscription_ends_on) { Time.zone.at(current_period_end).as_json }
  let(:created_subscription) do
    {
      plan: { id: 'price_random_number', product: 'prod_random_number' },
      quantity: 2,
      status: 'active',
      current_period_end: current_period_end
    }.with_indifferent_access
  end

  describe '#perform' do
    before do
      create(
        :installation_config,
        { name: 'CHATWOOT_CLOUD_PLANS', value: [
          { 'name' => 'A Plan Name', 'product_id' => ['prod_hacker_random'], 'price_ids' => ['price_hacker_random'] }
        ] }
      )
    end

    it 'preserves unrelated custom attributes, clears is_creating_customer, and reconciles default-plan features' do
      account.update!(
        custom_attributes: {
          'is_creating_customer' => true,
          'onboarding_source' => 'billing_page',
          'subscription_status' => 'past_due',
          'subscription_ends_on' => 1.day.ago
        }
      )
      account.enable_features!(:help_center)

      customer = double
      allow(Stripe::Customer).to receive(:create).and_return(customer)
      allow(customer).to receive(:id).and_return('cus_random_number')
      allow(Stripe::Subscription).to receive(:create).and_return(created_subscription)

      create_stripe_customer_service.new(account: account).perform

      expect(account.reload.custom_attributes).to include(
        'stripe_customer_id' => customer.id,
        'stripe_price_id' => 'price_random_number',
        'stripe_product_id' => 'prod_random_number',
        'subscribed_quantity' => 2,
        'plan_name' => 'A Plan Name',
        'onboarding_source' => 'billing_page',
        'subscription_status' => 'active',
        'subscription_ends_on' => subscription_ends_on
      )
      expect(account.custom_attributes).not_to have_key('is_creating_customer')
      expect(account).not_to be_feature_enabled('help_center')
    end

    it 'does not call stripe methods if customer id is present' do
      account.update!(custom_attributes: { stripe_customer_id: 'cus_random_number' })
      allow(subscriptions_list).to receive(:data).and_return([])
      allow(Stripe::Customer).to receive(:create)
      allow(Stripe::Subscription).to receive(:list).and_return(subscriptions_list)
      allow(Stripe::Subscription).to receive(:create).and_return(created_subscription)

      create_stripe_customer_service.new(account: account).perform

      expect(Stripe::Customer).not_to have_received(:create)
      expect(Stripe::Subscription)
        .to have_received(:create)
        .with({ customer: 'cus_random_number', items: [{ price: 'price_hacker_random', quantity: 2 }] })

      expect(account.reload.custom_attributes).to eq(
        {
          stripe_customer_id: 'cus_random_number',
          stripe_price_id: 'price_random_number',
          stripe_product_id: 'prod_random_number',
          subscribed_quantity: 2,
          plan_name: 'A Plan Name',
          subscription_status: 'active',
          subscription_ends_on: subscription_ends_on,
          subscription_cancels_on: nil,
          billing_currency: 'usd'
        }.with_indifferent_access
      )
    end

    it 'calls stripe methods to create a customer and updates the account' do
      customer = double
      allow(Stripe::Customer).to receive(:create).and_return(customer)
      allow(customer).to receive(:id).and_return('cus_random_number')
      allow(Stripe::Subscription).to receive(:create).and_return(created_subscription)

      create_stripe_customer_service.new(account: account).perform

      expect(Stripe::Customer).to have_received(:create).with(
        { name: account.name, email: admin1.email }
      )
      expect(Stripe::Subscription)
        .to have_received(:create)
        .with({ customer: customer.id, items: [{ price: 'price_hacker_random', quantity: 2 }] })

      expect(account.reload.custom_attributes).to eq(
        {
          stripe_customer_id: customer.id,
          stripe_price_id: 'price_random_number',
          stripe_product_id: 'prod_random_number',
          subscribed_quantity: 2,
          plan_name: 'A Plan Name',
          subscription_status: 'active',
          subscription_ends_on: subscription_ends_on,
          subscription_cancels_on: nil,
          billing_currency: 'usd'
        }.with_indifferent_access
      )
    end

    it 'sets the billing country override when the account currency requires it' do
      with_modified_env ENABLE_MULTI_CURRENCY_BILLING: 'true' do
        account.update!(custom_attributes: { billing_currency: 'brl' })
        customer = double
        allow(Stripe::Customer).to receive(:create).and_return(customer)
        allow(customer).to receive(:id).and_return('cus_random_number')
        allow(Stripe::Subscription).to receive(:create).and_return(created_subscription)

        create_stripe_customer_service.new(account: account).perform

        expect(Stripe::Customer).to have_received(:create).with(
          { name: account.name, email: admin1.email, address: { country: 'BR' }, preferred_locales: ['pt-BR'] }
        )
      end
    end
  end

  describe 'when checking for existing subscriptions' do
    before do
      create(
        :installation_config,
        { name: 'CHATWOOT_CLOUD_PLANS', value: [
          { 'name' => 'A Plan Name', 'product_id' => ['prod_hacker_random'], 'price_ids' => ['price_hacker_random'] }
        ] }
      )
    end

    context 'when account has no stripe_customer_id' do
      it 'creates a new subscription' do
        customer = double
        allow(Stripe::Customer).to receive(:create).and_return(customer)
        allow(customer).to receive(:id).and_return('cus_random_number')
        allow(Stripe::Subscription).to receive(:create).and_return(created_subscription)

        create_stripe_customer_service.new(account: account).perform

        expect(Stripe::Customer).to have_received(:create)
        expect(Stripe::Subscription).to have_received(:create)
      end
    end

    context 'when account has stripe_customer_id' do
      let(:stripe_customer_id) { 'cus_random_number' }

      before do
        account.update!(custom_attributes: { stripe_customer_id: stripe_customer_id })
      end

      context 'when customer has an active non-default subscription' do
        before do
          allow(Stripe::Subscription).to receive(:list).and_return(subscriptions_list)
          allow(subscriptions_list).to receive(:data).and_return([{ 'plan' => { 'id' => 'price_paid_plan' } }])
          allow(Stripe::Subscription).to receive(:create)
        end

        it 'does not create a new subscription' do
          create_stripe_customer_service.new(account: account).perform

          expect(Stripe::Subscription).not_to have_received(:create)
          expect(Stripe::Subscription).to have_received(:list).with(
            {
              customer: stripe_customer_id,
              status: 'active',
              limit: 1
            }
          )
        end
      end
    end
  end

  # Two Stripe round trips sit between the read of `custom_attributes` and the write of it, and the
  # write is the whole column. Anything another writer put in the row during those calls is erased,
  # and anything it deleted comes back. No threads: the window is the network call.
  describe 'when another writer lands on the account during the stripe calls' do
    let(:customer) { double }

    before do
      create(
        :installation_config,
        { name: 'CHATWOOT_CLOUD_PLANS', value: [
          { 'name' => 'A Plan Name', 'product_id' => ['prod_hacker_random'], 'price_ids' => ['price_hacker_random'] }
        ] }
      )
      allow(Stripe::Customer).to receive(:create).and_return(customer)
      allow(customer).to receive(:id).and_return('cus_random_number')
    end

    # The shape of a job that enriches the account while the customer is being created: it writes a
    # key this service never read, so nothing about it is in the copy being written back.
    it 'keeps a key written during the calls' do
      account.update!(custom_attributes: { 'is_creating_customer' => true })
      allow(Stripe::Subscription).to receive(:create) do
        Account.where(id: account.id)
               .update_all("custom_attributes = custom_attributes || '{\"branding_enriched\": true}'::jsonb") # rubocop:disable Rails/SkipsModelValidations
        created_subscription
      end

      create_stripe_customer_service.new(account: account).perform

      expect(account.reload.custom_attributes).to include('branding_enriched' => true, 'stripe_customer_id' => 'cus_random_number')
      expect(account.custom_attributes).not_to have_key('is_creating_customer')
    end

    # The same window, on a key the service did read and does not write. Merging the whole copy back
    # would return the value to what it was when the copy was taken.
    it 'keeps the new value of a key it read and does not write' do
      account.update!(custom_attributes: { 'is_creating_customer' => true, 'onboarding_source' => 'billing_page' })
      allow(Stripe::Subscription).to receive(:create) do
        Account.where(id: account.id)
               .update_all("custom_attributes = custom_attributes || '{\"onboarding_source\": \"signup\"}'::jsonb") # rubocop:disable Rails/SkipsModelValidations
        created_subscription
      end

      create_stripe_customer_service.new(account: account).perform

      expect(account.reload.custom_attributes).to include('onboarding_source' => 'signup')
      expect(account.custom_attributes).not_to have_key('is_creating_customer')
    end

    # `finish_onboarding` deletes this key, and the copy read before the calls still has it: rewriting
    # the column puts the user back on the step they had just left.
    it 'leaves a key deleted during the calls deleted' do
      account.update!(custom_attributes: { 'is_creating_customer' => true, 'onboarding_step' => 'inbox_setup' })
      allow(Stripe::Subscription).to receive(:create) do
        Account.where(id: account.id)
               .update_all("custom_attributes = custom_attributes - 'onboarding_step'") # rubocop:disable Rails/SkipsModelValidations
        created_subscription
      end

      create_stripe_customer_service.new(account: account).perform

      expect(account.reload.custom_attributes).not_to have_key('onboarding_step')
      expect(account.custom_attributes).not_to have_key('is_creating_customer')
    end
  end

  # The downgrade path: `HandleStripeEventService#process_subscription_deleted` hands over an account
  # whose column still says the paid plan, and reads what this service does to it right afterwards.
  describe 'when the subscription that was deleted leaves the account on the default plan' do
    let(:customer) { double }

    before do
      create(
        :installation_config,
        { name: 'CHATWOOT_CLOUD_PLANS', value: [
          { 'name' => 'A Plan Name', 'product_id' => ['prod_hacker_random'], 'price_ids' => ['price_hacker_random'] }
        ] }
      )
      account.update!(custom_attributes: { 'stripe_customer_id' => 'cus_random_number', 'plan_name' => 'Business' })
      account.enable_features!(:sla, :custom_roles, :companies, :help_center)
      allow(Stripe::Subscription).to receive(:list).and_return(subscriptions_list)
      allow(subscriptions_list).to receive(:data).and_return([])
      allow(Stripe::Subscription).to receive(:create).and_return(created_subscription)
    end

    # `ReconcilePlanFeaturesService` decides the feature set from `account.custom_attributes['plan_name']`
    # on the object in memory, so a write that lands in the row without refreshing that object leaves
    # the paid features on for an account that has just lost its subscription.
    it 'reconciles the features against the plan it just wrote' do
      create_stripe_customer_service.new(account: account).perform

      expect(account.reload.custom_attributes).to include('plan_name' => 'A Plan Name')
      expect(account).not_to be_feature_enabled('sla')
      expect(account).not_to be_feature_enabled('custom_roles')
      expect(account).not_to be_feature_enabled('companies')
      expect(account).not_to be_feature_enabled('help_center')
    end

    # The caller's next line is `account.with_lock`, which raises on a receiver carrying unsaved
    # changes, so the account it handed over has to come back clean.
    it 'hands the account back with nothing pending on it' do
      create_stripe_customer_service.new(account: account).perform

      expect(account).not_to be_changed
      expect { account.with_lock { nil } }.not_to raise_error
    end

    # The retry of a run that wrote the row and then failed before reconciling: the merge finds the
    # keys already there and writes nothing, and the features are still the ones of the plan that
    # ended. Reconciling only when the row changed leaves them that way for good.
    it 'reconciles the features even when the row already says the plan' do
      create_stripe_customer_service.new(account: account).perform
      account.reload.enable_features!(:sla, :companies)

      create_stripe_customer_service.new(account: account).perform

      expect(account.reload).not_to be_feature_enabled('sla')
      expect(account).not_to be_feature_enabled('companies')
    end

    # `process_subscription_deleted` reads the answer as `return unless ... perform`, so a run that
    # found everything already written must still say it worked.
    it 'still answers true on a second run that writes nothing' do
      create_stripe_customer_service.new(account: account).perform
      # The default plan's own subscription, so the run gets past the guard that refuses a paid one
      # and reaches the write with everything already in the row.
      allow(subscriptions_list).to receive(:data).and_return(
        [created_subscription.merge(plan: { id: 'price_hacker_random', product: 'prod_hacker_random' })]
      )

      expect(create_stripe_customer_service.new(account: account.reload).perform).to be(true)
    end
  end
end

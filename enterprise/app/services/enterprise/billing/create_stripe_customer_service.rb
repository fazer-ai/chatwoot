class Enterprise::Billing::CreateStripeCustomerService
  include BillingHelper

  pattr_initialize [:account!]

  DEFAULT_QUANTITY = 2

  def perform
    active_sub = active_subscription
    return false if active_sub && !default_plan_subscription?(active_sub)

    customer_id = prepare_customer_id
    subscription = active_sub || Stripe::Subscription.create(customer: customer_id, items: [{ price: price_id, quantity: default_quantity }])

    # Only the keys this service computes, merged into the row as it stands. Two Stripe round trips
    # sit between the read above and this write, and writing the whole column back erased whatever
    # landed in the row during them: a key another job added, a value someone changed, a key the
    # onboarding controller deleted. `remove:` is applied before the merge, which is why the flag has
    # to be taken off here and not carried inside the hash being merged.
    account.merge_json_column!(:custom_attributes, merge: stripe_attributes(customer_id, subscription), remove: ['is_creating_customer'])
    # The merge writes a row it loaded on its own and leaves this object untouched, by design. The
    # reconciliation below reads `plan_name` off it to decide the feature set, so without this it
    # would read the plan the account was on before: on the subscription-deleted path that is the
    # paid plan, and the features of a subscription that has just ended would stay on.
    account.reload
    Enterprise::Billing::ReconcilePlanFeaturesService.new(account: account).perform
    true
  end

  private

  def prepare_customer_id
    customer_id = account.custom_attributes['stripe_customer_id']
    customer_id = Stripe::Customer.create(customer_params).id if customer_id.blank?
    customer_id
  end

  # Only currencies that need a country override (e.g. BRL/PIX) set address/locale; usd keeps Stripe defaults.
  def customer_params
    params = { name: account.name, email: billing_email }
    country = Enterprise::Billing::Currencies.country_for(account.billing_currency)
    return params if country.blank?

    params.merge(
      address: { country: country },
      preferred_locales: [Enterprise::Billing::Currencies.preferred_locale_for(account.billing_currency)]
    )
  end

  def default_quantity
    default_plan['default_quantity'] || DEFAULT_QUANTITY
  end

  def billing_email
    account.administrators.first.email
  end

  def default_plan
    @default_plan ||= Enterprise::Billing::PlanConfiguration.default_plan
  end

  def price_id
    Enterprise::Billing::PlanConfiguration.price_id_for(default_plan, account.billing_currency)
  end

  def active_subscription
    stripe_customer_id = account.custom_attributes['stripe_customer_id']
    return nil if stripe_customer_id.blank?

    Stripe::Subscription.list(
      {
        customer: stripe_customer_id,
        status: 'active',
        limit: 1
      }
    ).data.first
  end

  def default_plan_subscription?(subscription)
    Enterprise::Billing::PlanConfiguration.plan_contains_product_id?(default_plan, subscription['plan']['product'])
  end

  def stripe_attributes(customer_id, subscription)
    {
      'stripe_customer_id' => customer_id,
      'stripe_price_id' => subscription['plan']['id'],
      'stripe_product_id' => subscription['plan']['product'],
      'plan_name' => default_plan['name'],
      'subscribed_quantity' => subscription['quantity'],
      'subscription_status' => subscription['status'],
      # Serialized here rather than left as a Time. The column stores it as this same string, so the
      # value is unchanged, but the merge compares what it is about to write against what the row
      # holds: a Time never equals the string that came back, and every run would write again and
      # fire the account's callbacks for nothing.
      'subscription_ends_on' => subscription_ends_on(subscription).as_json,
      'billing_currency' => billing_currency_for(subscription)
    }
  end

  # Persist the currency Stripe actually billed, read straight from the price; the
  # requested currency may lack a configured price and fall back to usd.
  def billing_currency_for(subscription)
    Enterprise::Billing::Currencies.to_supported(subscription['plan']['currency'])
  end
end

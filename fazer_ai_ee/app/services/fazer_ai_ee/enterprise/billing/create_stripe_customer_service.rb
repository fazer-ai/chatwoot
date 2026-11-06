# Only the keys this service computes are merged into the row as it stands. Two Stripe round
# trips sit between upstream's read of `custom_attributes` and its write of the whole column,
# and that write erased whatever landed in the row during them. `perform` is copied whole
# because the write sits in its middle; upstream_overrides_spec.rb fingerprints the original.
module FazerAiEe::Enterprise::Billing::CreateStripeCustomerService
  def perform
    active_sub = active_subscription
    return false if active_sub && !default_plan_subscription?(active_sub)

    customer_id = prepare_customer_id
    subscription = active_sub || Stripe::Subscription.create(customer: customer_id, items: [{ price: price_id, quantity: default_quantity }])

    # `remove:` is applied before the merge, which is why the flag is taken off here and not
    # carried inside the hash being merged.
    account.merge_json_column!(:custom_attributes, merge: stripe_attributes(customer_id, subscription), remove: ['is_creating_customer'])
    # The merge writes a row it loaded on its own and leaves this object untouched. The
    # reconciliation reads `plan_name` off it, so without this it would read the plan the
    # account was on before: on the subscription-deleted path that is the paid plan.
    account.reload
    Enterprise::Billing::ReconcilePlanFeaturesService.new(account: account).perform
    true
  end

  private

  def stripe_attributes(customer_id, subscription)
    {
      'stripe_customer_id' => customer_id,
      'stripe_price_id' => subscription['plan']['id'],
      'stripe_product_id' => subscription['plan']['product'],
      'plan_name' => default_plan['name'],
      'subscribed_quantity' => subscription['quantity'],
      'subscription_status' => subscription['status'],
      # Serialized here, as the column stores it: the merge compares what it writes against what
      # the row holds, and a Time never equals the string that came back.
      'subscription_ends_on' => subscription_ends_on(subscription).as_json,
      'subscription_cancels_on' => subscription_cancels_on(subscription).as_json,
      'billing_currency' => billing_currency_for(subscription)
    }
  end
end

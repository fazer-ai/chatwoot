json.payload do
  json.array! @loss_reasons do |loss_reason|
    json.partial! 'api/v1/accounts/loss_reasons/loss_reason', formats: [:json], loss_reason: loss_reason
  end
end

json.payload do
  json.array! @funnel_stages do |stage|
    json.partial! 'funnel_stage', stage: stage
  end
end

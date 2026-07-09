json.meta do
  # `total_count` is unpaged so the frontend can render "1-25 of 143" without
  # a second request. Kept explicit — kaminari's `count` on a paginated
  # relation triggers a second COUNT(*) query but no records fetch.
  json.total_count @tickets.total_count
  json.current_page @tickets.current_page
  json.per_page @tickets.limit_value
end

json.payload do
  json.array!(@tickets) do |ticket|
    json.partial! 'ticket', ticket: ticket
  end
end

json.data do
  json.payload do
    json.array! @notifications, partial: 'notification', as: :pair
  end
end

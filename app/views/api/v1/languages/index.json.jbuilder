json.data do
  json.array! @languages do |language|
    json.partial! 'api/v1/models/language', resource: language
  end
end

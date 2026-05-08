json.data do
  json.array! @releases do |release|
    json.tag release['tag']
    json.published_at release['published_at']
    json.url release['url']
    json.notes do
      json.en release.dig('notes', 'en')
      json.pt_BR release.dig('notes', 'pt_BR')
    end
  end
end

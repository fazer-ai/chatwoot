json.array! @disparos do |disparo|
  json.partial! 'disparo', disparo: disparo
end

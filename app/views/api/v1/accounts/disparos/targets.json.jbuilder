json.array! @targets do |target|
  json.partial! 'target', target: target
end

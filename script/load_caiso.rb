require_relative "../lib/db.rb"
require 'json'


# I think this list might be incomplete.
path = '/Users/ari/src/ideal_grid/data/caiso_nodes.json' 
json = JSON.load File.read(path)

json.each do |name, lat, lon|
  loc = Point.create :lon => lon, :lat => lat
  Load.create :name => name, :region => "CAISO", :point => loc 
end

require 'pry'
binding.pry

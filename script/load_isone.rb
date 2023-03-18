require_relative "../lib/db.rb"
require 'csv'

# There's no way this is complete
path = '/Users/ari/src/ideal_grid/data/isone_nodes.csv' 
points = CSV.read(open(path))[1..-1]

points.each do |name, lat, lon|
  loc = Point.create :lon => lon.to_f, :lat => lat.to_f
  Load.create :name => name, :region => "ISO-NE", :point => loc
end

require 'pry'
binding.pry


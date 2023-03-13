require_relative "../lib/db.rb"
require 'csv'

path = '/Users/ari/src/ideal_grid/data/isone_nodes.csv' 
points = CSV.read(open(path))[1..-1]

points.each do |name, lat, lon|
  Load.create :name => name, :region => "ISO-NE", :lon => lon.to_f, :lat => lat.to_f
end

require 'pry'
binding.pry


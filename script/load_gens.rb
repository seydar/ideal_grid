require_relative "../lib/db.rb"
require 'csv'

path = '/Users/ari/src/ideal_grid/data/power_plants_simple.csv' 
points = CSV.read(open(path))[1..-1]

points.each do |gen|
  loc = Point.create :lat  => gen[1].to_f,
                     :lon  => gen[2].to_f
  Source.create :name => gen[0],
                :point => loc,
                :naics_desc => gen[3],
                :oper_cap => gen[4].to_f,
                :summer_cap => gen[5].to_f,
                :winter_cap => gen[6].to_f,
                :gen_units => gen[7].to_i,
                :lines => gen[8].to_i
end

require 'pry'
binding.pry


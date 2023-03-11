require 'sequel'

base = File.dirname __FILE__
path = File.join base, "../db/grid.db"
DB = Sequel.connect "sqlite://#{path}"

class Load < Sequel::Model
  many_to_many :edges

DB.create_table? :loads do
  primary_key :id
  String :name
  String :region
  Float :lat
  Float :lon
  Float :max_peak_load
end

end

DB.create_table? :line_points do
  primary_key :id
  Float :lat
  Float :lon
end



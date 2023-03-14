require 'sequel'

base = File.dirname __FILE__
path = File.join base, "../db/grid.db"
DB = Sequel.connect "sqlite://#{path}"

# Since the graphs that are produced can be modified, I want to make sure that
# the graphs used are separate from the immutable DB of ground-truth data.
#
# Thus, `Load` and `Line` should be separate from `Node` and `Edge`: the loads
# and lines will be read from the DB and then turned into Nodes and Edges,
# where they can be manipulated without fear. Yeah yeah, theoretically
# everything is fine if you don't call `#save`, but I'm not willing to risk it.
#
# Plus, I think having a lighter-weight class for manipulation is probably
# smart.

DB.create_table? :loads do
  primary_key :id
  String :name
  String :region
  Float :lat
  Float :lon
  Float :max_peak_load
end

class Load < Sequel::Model
  many_to_many :lines

  alias_method :x, :lon
  alias_method :y, :lat
end

DB.create_table? :lines do
  primary_key :id
  foreign_key :left_id,  :class => Load
  foreign_key :right_id, :class => Load
  Float :length # calculable, but prolly worth storing
end

class Line < Sequel::Model
  many_to_many :loads
end

DB.create_table? :sources do
  primary_key :id
  String :name
  Float :lat
  Float :lon
  String :naics_desc
  Float :oper_cap
  Float :winter_cap
  Float :summer_cap
  Integer :gen_units
  Integer :lines
end

class Source < Sequel::Model
  alias_method :x, :lon
  alias_method :y, :lat
end


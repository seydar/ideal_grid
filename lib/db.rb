require 'sequel'
require 'logger'

base = File.dirname __FILE__
path = File.join base, "../db/grid.db"
DB = Sequel.connect "sqlite://#{path}",
                    #:loggers => [Logger.new($stdout)] # for verbose DB access
                    :loggers => []

# Since the graphs that are produced can be modified (edges added and deleted),
# I want to make sure that the graphs used are separate from the immutable DB
# of ground-truth data.
#
# Thus, `Load` and `Line` should be separate from `Node` and `Edge`: the loads
# and lines will be read from the DB and then turned into Nodes and Edges,
# where they can be manipulated without fear. Yeah yeah, theoretically
# everything is fine if you don't call `#save`, but I'm not willing to risk it.
#
# Plus, I think having a lighter-weight class for manipulation is probably
# smart.

DB.create_table? :points do
  primary_key :id
  Float :lat
  Float :lon
end

class Point < Sequel::Model
  many_to_many :lines, :jointable => :lines

  def self.within(box)
    filter(:lon => box[:w]..box[:e], :lat => box[:s]..box[:n]).all
  end

  alias_method :x, :lon
  alias_method :y, :lat

  # uhoh... code duplication
  def euclidean_distance(p_2)
    Math.sqrt((self.x - p_2.x) ** 2 + (self.y - p_2.y) ** 2)
  end

  def buffer(miles)
    dg = miles / 60.0

    {:n => y + dg,
     :s => y - dg,
     :e => x + dg,
     :w => x - dg}
  end
end

DB.create_table? :loads do
  primary_key :id
  String :name
  String :region
  Float :max_peak_load
  foreign_key :point_id, :class => Point
end

class Load < Sequel::Model
  # https://sequel.jeremyevans.net/rdoc/files/doc/association_basics_rdoc.html#label-Differences+Between+many_to_one+and+one_to_one
  many_to_one :point # not accurate but fuck it. 

  def self.within(box)
    pts = Point.within box
    eager(:point).filter(:point => pts).all
  end

  def x; point.x; end
  def y; point.y; end
end

DB.create_table? :lines do
  primary_key :id
  foreign_key :left_id,  :class => Point
  foreign_key :right_id, :class => Point
  Float :length # calculable, but prolly worth storing
  Float :voltage
end

# This tracks edges
class Line < Sequel::Model
  many_to_one :left,  :class => Point
  many_to_one :right, :class => Point

  # NH/Vt
  #box = {:n =>  44.1793, :s =>  43.8583,
  #       :e => -71.8985, :w => -72.2598}
  
  # New England
  #box = {:n =>  45.01, :s =>  42.71,
  #       :e => -71.01, :w => -73.25}
  
  # Michigan
  #box = {:n =>  45.82, :s =>  41.80,
  #       :e => -82.72, :w => -86.12}
  def self.within(box)
    pts = Point.within box
    filter(Sequel.or(:left => pts, :right => pts)).all
  end
end

DB.create_table? :sources do
  primary_key :id
  foreign_key :point_id, :class => Point
  String :name
  String :naics_desc
  Float :oper_cap
  Float :winter_cap
  Float :summer_cap
  Integer :gen_units
  Integer :lines
end

class Source < Sequel::Model
  # https://sequel.jeremyevans.net/rdoc/files/doc/association_basics_rdoc.html#label-Differences+Between+many_to_one+and+one_to_one
  many_to_one :point # not accurate but fuck it

  def self.within(box)
    pts = Point.within box
    #eager(:point).filter{ (oper_cap > 0) | {:point => pts} }.all
    eager(:point).filter(:point => pts).all
  end

  def self.by_fuel_mix(ratios, &filt)
    sources = eager(:point).filter(&filt).all

    # Turn those fractions into actual generators!
    # Take a random sampling.
    # There's gotta be a better way to do this.
    ratios.map do |type, perc|
      srcs = sources.filter {|s| s.naics_desc == type.to_s.upcase }
      srcs.sample (perc * srcs.size).floor, :random => PRNG
    end.flatten
  end

  def x; point.x; end
  def y; point.y; end
end


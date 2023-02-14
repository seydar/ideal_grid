require "overpass_api_ruby"
require 'json'
require_relative 'lib/graph/edge.rb'
require_relative 'lib/graph/node.rb'
require_relative 'plotting.rb'
require_relative 'lib/unionf.rb'

class Polygon
  attr_accessor :points

  def initialize(pts)
    @points = pts
  end

  def inspect
    "#<Polygon: #{points.size} points>"
  end

  def smooth(epsilon=2e-4, preserve=[])
    Polygon.new r_d_p(points, epsilon, preserve)
  end

  # Ramer-Douglas-Peucker algorithm
  # Wrote this once upon a time in Python back in the Navy. Beautiful algorithm
  # to have to your back pocket.
  def r_d_p(pts, epsilon=2e-4, preserve=[])
    return pts if pts.size <= 2

    max = 0
    idx = -1

    # No need to check the first and last points
    # Kinda wish I could make this shorter though
    pts[0..-2].each.with_index do |pt, i|
      # Don't test the first one
      # but we want i to start at 1 for when it matters
      # and I think this keeps the rest of the code clear
      next if i == 0

      if preserve.include? pt
        idx = i
        max = epsilon + 1 # arbitrary, just needs to be greater than epsilon
        break
      end

      dist = distance pt, pts[0], pts[-1]
      if dist > max
        max = dist
        idx = i
      end
    end

    if max > epsilon
      # Combine the two halves and strip the duplicated point
      # Ruby lets me make this one-liner almost too golfy
      #
      # Pass on the nodes we'd like to preserve and ensure that we NEVER remove
      r_d_p(pts[0..idx], epsilon, preserve) +
        r_d_p(pts[idx..-1], epsilon, preserve)[1..-1]
    else
      [pts[0], pts[-1]]
    end
  end

  # perpendicular distance from `p0` to the ray that passes
  # through `p1` and `p2`
  def distance(p0, p1, p2)
    numerator   = (((p2.x - p1.x) * (p1.y - p0.y)) -
                   ((p1.x - p0.x) * (p2.y - p1.y))).abs
    denominator = Math.sqrt((p2.x - p1.x) ** 2 + (p2.y - p1.y) ** 2)

    numerator / denominator
  end
end

def download_overpass
  query = "way['power'='line'];(._;>;);out body;"
  
  options = {:bbox => {:n =>  45.01, :s =>  42.71,
                       :e => -71.01, :w => -73.25}}
  #options = {:bbox => {:n =>  45.3154, :s =>  44.6424,
  #                     :e => -71.9248, :w => -72.627}}
  
  overpass = OverpassAPI::QL.new options
  response = overpass.query query

  lines = response[:elements].filter {|e| e[:type] == "way" }
  nodes = response[:elements].filter {|e| e[:type] == "node" }.map do |n|
    [n[:id], Node.new(n[:lon], n[:lat], :id => n[:id])]
  end.to_h
  
  $nodes = nodes.values
  $nodes.each {|n| n.load = 0 }
  
  lines.each do |line|
    line[:nodes]   = line[:nodes].map {|id| nodes[id] }
  end

  lines
end

def within(box, pt)
  pt.y < box[:n] &&
    pt.y > box[:s] &&
    pt.x < box[:e] &&
    pt.x > box[:w]
end

def read_geojson(path, box=nil)
  dedup = {}
  json  = JSON.load File.read(path)
  lines = json["features"]

  lines.each do |line|
    line[:nodes] = line['geometry']["coordinates"].map do |coord|
      dedup[coord] ||= Node.new(coord[0], coord[1], :id => dedup.size)
      dedup[coord].load = 0
      dedup[coord]
    end
  end

  if box
    lines.each do |line|
      line[:nodes] = line[:nodes].filter {|n| within box, n }
    end

    lines = lines.filter {|l| not l[:nodes].empty? }
  end

  $nodes = lines.map {|l| l[:nodes] }.flatten

  lines.each do |line|
    line[:polygon] = Polygon.new line[:nodes]
    line[:color] = COLORS.sample
  end
end

def simplify(lines)
  # Track the nodes that are joints between lines
  # so that we can pass those in to the polygon simplification algorithm
  # to preserve those nodes
  #
  # R-D-P algorithm only works on a line, which means that each node can only
  # 
  # We can combine all of the points in the polygons and look at which
  # points are duplicated: THOSE are the ones we need to preserve
  full  = lines.map {|l| l[:nodes] }.flatten
  singles  = Set.new # This will make the `include?` call faster
  preserve = []
  full.each.with_index do |n, i|
    if singles.include? n.to_a
      preserve << n
    else
      singles << n.to_a
    end
  end
  
  
  lines.each do |line|
    line[:smooth] = line[:polygon].smooth 2e-4, preserve
  end
end

def super_simplify(lines)
  # Ugh have to recalculate this
  full  = lines.map {|l| l[:nodes] }.flatten
  singles  = Set.new # This will make the `include?` call faster
  preserve = Set.new
  full.each.with_index do |n, i|
    if singles.include? n.to_a
      preserve << n.to_a
    else
      singles << n.to_a
    end
  end

  # Need to add edge length into this somehow
  lines.each do |line|
    line[:save] = line[:nodes].filter.with_index do |pt, i|
      # first, last, or a junction node
      i == 0 or
        i == line[:nodes].size - 1 or
        preserve.include? pt.to_a
    end

    line[:super] = Polygon.new line[:save]
  end
end

def build_edges(poly)
  poly.points.each_cons(2).map do |left, right|
    e = Edge.new left, right # deal with the length later
    e.mark_nodes!
    e
  end
end

def show_poly(lines, poly)
  $plot = Gnuplot::Plot.new

  # Make connected lines have the same color
  # (instead of actually joining the polygons, we've merely joined them
  # in the U-F)
  lines.each {|l| l[:raw] = l[:nodes].map(&:to_a) }
  
  uf = UnionF.new lines
  #(0..lines.size - 1).each do |i|
  #  (i..lines.size - 1).each do |j|
  #    if lines[i][:raw] & lines[j][:raw] != []
  #      uf.union lines[i], lines[j]
  #    end
  #  end
  #end

  lines.each do |line|
    plot_edges line[:edges]
  end
  
  uf.disjoint_sets.each do |set|
    color = set[0][:color]
    set.each do |line|
      plot_points line[poly].points, :color => color
    end
  end

  show_plot
end

def time(desc, &block)
  puts desc
  start = Time.now
  res = block.call
  puts " => #{Time.now - start}"
  res
end

##########################################################
##########################################################
##########################################################
##########################################################
##########################################################
##########################################################
##########################################################
##########################################################
##########################################################

box = {:n =>  44.1793, :s =>  43.8583,
       :e => -71.8985, :w => -72.2598}

lines = nil
time "Loading" do
  #lines = download_overpass
  lines = read_geojson "/Users/ari/src/ideal_grid/Transmission_Lines.geojson", box
  
  puts "Lines: #{lines.size}"
  
  puts "Full:"
  puts "\tTotal nodes: #{lines.sum {|l| l['geometry']["coordinates"].size }}"
  puts "\tDeduped nodes: #{lines.sum {|l| l[:nodes].size }}"
end

time "Simplify" do
  simplify lines
  
  ns = lines.sum {|l| l[:smooth].points.size }
  puts "Smoothed:"
  puts "\tNodes: #{ns}"
end

time "Super simplify" do
  super_simplify lines
  
  ns = lines.sum {|l| l[:super].points.size }
  puts "Supered:"
  puts "\tNodes: #{ns}"
end

type = :super

time "Building edges" do
  # Mark all the points on the smoothed lines
  # This should also take care of lines that use the same nodes
  lines.each {|l| l[:edges] = build_edges(l[type]) }
end

############################
# Plotting
# ##########################

# mess = [lines[36], lines[10], lines[11], lines[12]]

#require 'pry'
#binding.pry

time "plotting" do
  show_poly lines, type
end



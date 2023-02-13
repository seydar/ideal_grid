require "overpass_api_ruby"
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


query = "way['power'='line'];(._;>;);out body;"

options = {:bbox => {:n =>  45.01, :s =>  42.71,
                     :e => -71.01, :w => -73.25}}

overpass = OverpassAPI::QL.new options
response = overpass.query query

lines = response[:elements].filter {|e| e[:type] == "way" }
nodes = response[:elements].filter {|e| e[:type] == "node" }.map do |n|
  [n[:id], Node.new(n[:lon], n[:lat], :id => n[:id])]
end.to_h

$nodes = nodes.values

puts "Full:"
puts "\tNodes: #{nodes.size}"
puts "\tLines: #{lines.size}"

lines.each do |line|
  line[:nodes]   = line[:nodes].map {|id| nodes[id] }
  line[:polygon] = Polygon.new line[:nodes]
  line[:color] = COLORS.sample

  plot_points line[:polygon].points, :color => line[:color]
end

#show_plot

start = Time.now

# Okay, we know there are a lot of duplicates, but we don't know how they
# interrelate, so I think it's too soon to deduplicate them now

# Track the nodes that are joints between lines
# so that we can pass those in to the polygon simplification algorithm
# to preserve those nodes
#
# R-D-P algorithm only works on a line, which means that each node can only
# have a max of 2 edges (forward and backward)
#
# So we have to do the simplification on the lines *before* we join them

# So. Every line is duplicated, which means every node needs to
# be "preserved"... but we know that's not true.
# We can combine all of the points in the polygons and look at which
# points are duplicated: THOSE are the ones we need to preserve
full  = lines.map {|l| l[:nodes] }.flatten
singles  = Set.new
preserve = Set.new
pres_nodes = []
full.each.with_index do |n, i|
  if singles.include? n.to_a
    preserve << n.to_a
    pres_nodes << n
  else
    singles << n.to_a
  end
end

puts "#{Time.now - start} seconds"


$plot = Gnuplot::Plot.new

lines.each do |line|
  line[:smooth] = line[:polygon].smooth 2e-4, pres_nodes
  plot_points line[:smooth].points, :color => line[:color]
end

ns = lines.sum {|l| l[:smooth].points.size }
puts "Smoothed:"
puts "\tNodes: #{ns}"
puts "\tLines: #{lines.size}"

show_plot

# Find overlapping points and join them
#   This should be done with a Union-Find
# And then plot that
uf = UnionF.new lines
(0..lines.size - 1).each do |i|
  lines[i][:raw] ||= lines[i][:nodes].map(&:to_a)

  (i..lines.size - 1).each do |j|
    lines[j][:raw] ||= lines[j][:nodes].map(&:to_a)

    mut = lines[i][:raw] & lines[j][:raw]
    if lines[i][:raw] & lines[j][:raw] != []
      p mut.size
      uf.union lines[i], lines[j]
    end
  end
end

p uf.disjoint_sets.size

# Make connected lines have the same color
# (instead of actually joining the polygons, we've merely joined them
# in the U-F)
uf.disjoint_sets.each do |set|
  clr = COLORS.sample
  set.each {|l| l[:color] = clr }
end

$plot = Gnuplot::Plot.new

lines.each do |line|
  plot_points line[:smooth].points, :color => line[:color]
end

show_plot

require 'pry'
binding.pry


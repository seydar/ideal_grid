require_relative "../electric_avenue.rb"
require_relative "../scratch/polygon.rb"

#####################################
# How the fuck do I build a table piece-wise of all the transmission
# lines in the country? I save the points based on a simplification
# algorithm that's dependent on whatever set I'm looking at, so the
# junctures that join different areas could get fucked up.
#
# Ugh. Maybe I ultimately have to run the data on the entire country at
# once. Not fun.
#
# Maybe a lil bit of parallelization in the `join_points` method would make
# this palatable.
#####################################

def centroid(nodes)
  x = nodes.map {|n| n.x }.avg
  y = nodes.map {|n| n.y }.avg
  [x, y]
end

points = nil
lines = nil
time "Making lines" do
  lines = read_geojson ARGV[0]
  poly = :smooth
  lines.each {|l| l[:edges] = build_edges(l[poly]) }
  points = lines.map {|l| l[poly].points }.flatten.uniq
  puts "\t#{points.size} points"
end

#show_poly lines, :polygon

pts = nil
time "Getting the CG" do
  # This is the largest CG
  cg = DisjointGraph.new(points).connected_subgraphs.max_by {|cg| cg.size }
  pts = cg.nodes
  p pts.size
end

# okay
# 1. save the points that make up the lines
# 2. save the edges
#
# Part 1
made = pts.map do |point|
  [point.id, Point.create(:lon => point.x,
                          :lat => point.y)]
end.to_h

puts "#{pts.size} points created"

# Part 2
new_lines = pts.map {|p| p.edges }.flatten.uniq.map do |edge|
  nodes = edge.nodes.map {|n| made[n.id] }
  Line.create :left    => nodes[0],
              :right   => nodes[1],
              :length  => edge.length,
              :voltage => edge.voltage
end

puts "#{new_lines.size} lines created"


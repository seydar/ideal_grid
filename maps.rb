require_relative 'polygon.rb'

def time(desc, &block)
  puts desc
  start = Time.now
  res = block.call
  puts " => #{Time.now - start}"
  res
end

# We need to talk about this HIFLD data.
# It's got nodes that are within 800 feet of each other. It's got lines
# that parallel each other for their entireties.
#
# Are they different lines and nodes? Maybe.
#
#   "All models are wrong; some models are useful."
#
# I can sort out the details of this later on, but for now, it will be
# *most useful* if I merge some of these points and lines.
#
# Then, when I get some time off to focus on this, then I can remove the
# daylight between my model and reality.

box = {:n =>  44.1793, :s =>  43.8583,
       :e => -71.8985, :w => -72.2598}
box = {:n =>  45.01, :s =>  42.71,
       :e => -71.01, :w => -73.25}

PRNG = Random.new 1337

lines = nil
time "Loading" do
  #lines = download_overpass
  lines = read_geojson "/Users/ari/src/ideal_grid/Transmission_Lines.geojson", box
  #lines = lines.filter {|l| l["properties"]["INFERRED"] != "Y" }
  
  puts "Lines: #{lines.size}"
  
  puts "Full:"
  puts "\tTotal nodes: #{lines.sum {|l| l['geometry']["coordinates"].size }}"
  puts "\tDeduped nodes: #{lines.sum {|l| l[:nodes].size }}"
  $nodes = lines.map {|l| l[:nodes] }.flatten
end

#time "Simplify" do
#  simplify lines
#  
#  ns = lines.sum {|l| l[:smooth].points.size }
#  puts "Smoothed:"
#  puts "\tNodes: #{ns}"
#end
#
#time "Super simplify" do
#  super_simplify lines
#  
#  ns = lines.sum {|l| l[:super].points.size }
#  puts "Supered:"
#  puts "\tNodes: #{ns}"
#end

pts = nil
time "Join points" do
  poly = :polygon
  # Build these while the points are duplicated
  lines.each {|l| l[:edges] = build_edges(l[poly]) }

  # Now eliminate duplicates
  points = lines.map {|l| l[poly].points }.flatten.uniq

  # Now eliminate nearby points
  pts = join_points points, 0.03
  puts "\tJoined points: #{pts.size}"

  groups = group_by_connected pts

  # something to show off our work
  es = pts.map {|p| p.edges }.flatten
  plot_edges es

  groups.disjoint_sets.each.with_index do |set, i|
    plot_points set, :color => COLORS.sample(:random => PRNG)
  end
  show_plot

  require 'pry'
  binding.pry
end

############################
# Plotting
# ##########################

# mess = [lines[36], lines[10], lines[11], lines[12]]

uf = nil
time "plotting" do
  #uf = show_poly lines, :super
end



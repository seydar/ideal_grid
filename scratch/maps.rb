require_relative "../electric_avenue.rb"
require_relative "./polygon.rb"

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

# NH/VT
#box = {:n =>  44.1793, :s =>  43.8583,
#       :e => -71.8985, :w => -72.2598}

# New England Central
#box = {:n =>  45.01, :s =>  42.71,
#       :e => -71.01, :w => -73.25}

# Michigan
#box = {:n =>  45.82, :s =>  41.80,
#       :e => -82.72, :w => -86.12}

box = nil

lines = nil
time "Loading" do
  lines = read_geojson "/Users/ari/src/ideal_grid/data/isone/new_england_tx_lines.geojson", box
  #lines = read_geojson "/Users/ari/src/ideal_grid/data/michigan_lines.geojson", box

  $nodes = lines.map {|l| l[:nodes] }.flatten
  p $nodes.size
end

pts = nil
points = nil
time "joining" do
  poly = :smooth
  # Build these while the points are duplicated
  #lines.each {|l| l[:edges] = build_edges(l[poly]) }

  show_poly lines, poly

  # Now eliminate duplicates
  points = lines.map {|l| l[poly].points }.flatten.uniq

  p points.size

  # Now eliminate nearby points
  pts = join_points points, 0.03
  puts "\tJoined points: #{pts.size}"
end

time "coloring" do
  # something to show off our work
  es = pts.map {|p| p.edges }.flatten
  plot_edges es

  plot_points pts, :color => "gray"

  ## Loads
  #loads = Load.all.filter {|l| within box, l }
  #p "#{loads.size} loads"
  #plot_points loads, :color => "red"

  ## Generators
  #gens = Source.all.filter {|s| within box, s }
  #p "#{gens.size} gens"
  #plot_points gens, :color => "green"

  show_plot
end


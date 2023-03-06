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

# NH/Vt
#box = {:n =>  44.1793, :s =>  43.8583,
#       :e => -71.8985, :w => -72.2598}

# New England
#box = {:n =>  45.01, :s =>  42.71,
#       :e => -71.01, :w => -73.25}

# Michigan
box = {:n =>  45.82, :s =>  41.80,
       :e => -82.72, :w => -86.12}

PRNG = Random.new 1337

lines = nil
time "Loading" do
  #lines = read_geojson "/Users/ari/src/ideal_grid/data/new_england_lines.geojson", box
  lines = read_geojson "/Users/ari/src/ideal_grid/data/michigan_lines.geojson", box

  $nodes = lines.map {|l| l[:nodes] }.flatten
end

groups = nil
pts = nil
time "joining" do
  poly = :polygon
  # Build these while the points are duplicated
  lines.each {|l| l[:edges] = build_edges(l[poly]) }

  # Now eliminate duplicates
  points = lines.map {|l| l[poly].points }.flatten.uniq

  # Now eliminate nearby points
  pts = join_points points, 0.03
  puts "\tJoined points: #{pts.size}"

  groups = group_by_connected pts
end

time "coloring" do
  # something to show off our work
  es = pts.map {|p| p.edges }.flatten
  plot_edges es

  groups.disjoint_sets.each.with_index do |set, i|
    plot_points set, :color => COLORS.sample(:random => PRNG)
  end
  show_plot
end


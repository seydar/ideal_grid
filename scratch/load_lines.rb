require_relative "../lib/db.rb"
require_relative "../polygon.rb"

PRNG = Random.new 1337

#lines = read_geojson "/Users/ari/src/ideal_grid/data/new_england_lines.geojson", box
lines = read_geojson ARGV[0]
poly = :polygon
lines.each {|l| l[:edges] = build_edges(l[poly]) }
points = lines.map {|l| l[poly].points }.flatten.uniq
#pts = join_points points, 0.03
#deduplicate_edges pts

# FIXME
# Ugh.
# Turns out a lot of the points have 3 or 4 edges when they should only have 2.
# This appears to be because they have edges that bypass the more proximate nodes.
box = {:n=>44, :s=>43.7, :w=>-72, :e=>-71}
goal = Node.new -71.96, 43.8739

msub = points.filter {|p| within box, p }
morg = msub.sort_by {|p| p.euclidean_distance(goal) }

group_by_connected(msub).disjoint_sets.each do |set|
  plot_group set, :color => COLORS.sample(:random => PRNG)
end
show_plot

pts = join_points points, 0.03
deduplicate_edges pts
sub = pts.filter {|p| within box, p }
org = sub.sort_by {|p| p.euclidean_distance(goal) }

$plot = Gnuplot::Plot.new
plot_group sub
show_plot

# How do we know that we should drop edge #3 in `q.edges`?
q = sub.sort_by(&:x)[3]

require 'pry'
binding.pry


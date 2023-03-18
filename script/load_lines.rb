require_relative "../lib/db.rb"
require_relative "../polygon.rb"
require_relative "../lib/graph/graph.rb"
require_relative "../lib/monkey_patch.rb"

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



PRNG = Random.new 1337

#lines = read_geojson "/Users/ari/src/ideal_grid/data/new_england_lines.geojson", box
lines = read_geojson ARGV[0]
poly = :polygon
lines.each {|l| l[:edges] = build_edges(l[poly]) }
points = lines.map {|l| l[poly].points }.flatten.uniq
pts = join_points points, 0.03
deduplicate_edges pts

#bads = pts[14..16]
#cg = ConnectedGraph.new bads
#cyc = cg.shortest_cycle


# Ugh.
# Turns out a lot of the points have 3 or 4 edges when they should only have 2.
# This appears to be because they have edges that bypass the more proximate nodes.
#box = {:n=>44, :s=>43.7, :w=>-72, :e=>-71}
#goal = Node.new -71.96, 43.8739, :id => PRNG.rand
#
#msub = points.filter {|p| within box, p }
#morg = msub.sort_by {|p| p.euclidean_distance(goal) }
#
#group_by_connected(msub).disjoint_sets.each do |set|
#  plot_group set, :color => COLORS.sample(:random => PRNG)
#end
#show_plot

#pts = join_points points, 0.03
#deduplicate_edges pts
#sub = pts.filter {|p| within box, p }
#org = sub.sort_by {|p| p.euclidean_distance(goal) }
#
#$plot = Gnuplot::Plot.new
#plot_group sub
#show_plot
#
## How do we know that we should drop edge #3 in `q.edges`?
#q = sub.sort_by(&:x)[3]

# Get all the cycles
# Should probably filter them to make sure they're < 4 edges long
cycles = DisjointGraph.new(pts).connected_subgraphs.map {|cg| [cg, cg.shortest_cycle] }
cycles = cycles.filter {|cg, cyc| cyc }

def centroid(nodes)
  x = nodes.map {|n| n.x }.avg
  y = nodes.map {|n| n.y }.avg
  [x, y]
end

until cycles.empty?
  leave = false
  
  puts "#{cycles.size} cycles found! #{cycles.map {|c| c[1].size }}"
  
  # Drop the longest edge
  cycles.sort_by {|cyc| cyc.size }.each do |cg, cyc|
    # 6 was arbitrarily chosen because the cycles looked less weird
    if cyc.size >= 6 
      leave = true
      break
    end

    puts "cycle length #{cyc.size}"
    pp centroid(cyc)

    # Only nodes that are >= 3 edges, because otherwise they don't introduce
    # a cycle (unless it's an island, but I don't care about those)
    reduced = cyc.filter {|n| n.edges.size >= 3 }

    e = reduced.map(&:edges).flatten.uniq.max_by {|e| e.length }

    if e
      puts "\tdestroying #{e.inspect}"
      e.destroy! # detach it from the nodes

      # this is to balance out the `leave = true` below
      # If there's an island of 3 nodes that connect to each other, we
      # want to exit -- but what if there are other cycles in other CGs?
      # If we're here, then there was a cycle in another CG, so we want to
      # make sure we keep running and really prune out all of the cycles.
      leave = false 
    else
      # we've got an island — close on out of this
      leave = true
    end
  end

  cycles = cycles.map do |cg, _|
    cg.reset!
    [cg, cg.shortest_cycle]
  end

  break if leave
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

# Part 2
pts.map {|p| p.edges }.flatten.uniq.each do |edge|
  nodes = edge.nodes.map {|n| made[n.id] }
  Line.create :left   => nodes[0],
              :right  => nodes[1],
              :length => edge.length
end


#!/usr/bin/env ruby
require 'gnuplot'
require 'optimist'
require_relative 'k_means_pp.rb'
require_relative 'plotting.rb'
require_relative 'monkey_patch.rb'
Dir['./lib/**/*.rb'].each {|f| require_relative f }
require_relative 'filter_kruskal.rb'

opts = Optimist::options do
  banner <<-EOS
Pretend a minimal electric grid is a minimum spanning tree across a bunch of nodes.
Now cluster them to determine where to put your generators.
Now add in extra edges to add resiliency.
Now calculate the capacity of each of the lines.

Usage:
  grid.rb [options]
where [options] are:

EOS

  opt :parallel, "Parallelize the clustering algorithm"
  opt :nodes, "Number of nodes in the grid", :type => :integer, :default => 100
  opt :clusters, "Cluster the nodes into k clusters", :type => :integer, :default => 10
  opt :intermediate, "Show intermediate graphics of flow calculation"
end

grid, nodes, edges = nil
PRNG = Random.new 1138
$parallel = opts[:parallel]
$elapsed = 0
$intermediate = opts[:intermediate]

time "Edge production" do

  puts "parallel: #{$parallel}"

  # Generate a bunch of random points
  # We track IDs here so that equality can be asserted more easily after
  # objects have been copied due to parallelization (moving in and out of
  # processes -- they get marshalled and sent down a pipe)
  nodes = opts[:nodes].times.map do |i|
    n = Node.new(10 * PRNG.rand, 10 * PRNG.rand, :id => i)
    n.load = 1
    n
  end

  pairs = nodes.combination 2
  edges = pairs.map.with_index do |(p_1, p_2), i|
    Edge.new p_1,
             p_2,
             p_1.euclidean_distance(p_2),
             :id => i
  end

  puts "#{opts[:nodes]} nodes"
  puts "\t#{edges.size} edges in complete graph"
end

$nodes = nodes
update_ranges $nodes

def circle(nodes)
  nodes.size.times do |i|
    e = Edge.new nodes[i],
                 nodes[(i + 1) % nodes.size],
                 nodes[i].euclidean_distance(nodes[(i + 1) % nodes.size])
    nodes[i].edges << e
    nodes[(i + 1) % nodes.size].edges << e
  end
end

time "Tree production" do

  mst = []

  # Builds edges between nodes according to the MST
  parallel_filter_kruskal edges, UnionF.new(nodes), mst

  $algorithm = "Kruskal (since edges are too few)" if edges.size <= SEQ_THRESHOLD
  puts "Using #{$algorithm}"
  puts "\t#{mst.size} edges in MST"
end

time "Add initial generators [#{opts[:clusters]} clusters]" do

  grid = Grid.new nodes, []

  # Keep generators an array of arrays so we can track which generators were built
  # after which iteration
  graph = ConnectedGraph.new nodes

  # Needed for the global adjacency matrix for doing faster manhattan distance
  # calculations
  KMeansPP.graph = graph

  grid.generators = graph.generators_for_clusters grid do |size|
    opts[:clusters]
  end

  grid.calculate_reach!
  puts "\tGenerators: #{grid.generators.size}"
  puts "\tUnreachable: #{grid.unreached.size}"
end

time "Adding new generators via clustering" do
  connected_graphs = grid.unreached.connected_subgraphs
  puts "\tUnreached subgraph sizes: #{connected_graphs.map {|cg| cg.size }.inspect}"

  biguns = connected_graphs.filter {|cg| cg.size >  50 }
  #liluns = connected_graphs.filter {|cg| cg.size <= 50 }

  puts "\tClustering #{biguns.size} unreached subgraphs"
  biguns.each do |graph|
    cltrs = graph.size / opts[:clusters]
    grid.generators += graph.generators_for_clusters grid, cltrs do |size|
      opts[:clusters]
    end
  end

  puts "\tGenerators: #{grid.generators.size}"
  puts "\t\t#{grid.generators.map {|g| g.power }}"
end

time "Calculate reach" do

  # We have to figure out the reach so that we can restrict our viewing of
  # "which node is closest to which generator"
  grid.calculate_reach!

end

time "Calculate flow" do 

  # FIXME this is flawed
  #
  # Now that we know that everyone is connected (because we're dealing with
  # `grid.reach`), we get to sorta sort everyone by the generator that they're
  # closest to
  #
  # Actually, this is going to be a lot like the MST algorithm
  neighbors = []
  grid.reach.nodes.each do |node|
    grid.generators.each do |gen|
      neighbors << [node, gen, gen.node.path_to(node)]
    end
  end

  # Now -- just like in the MST algorithm -- we're going to sort them
  # and put them into the tree, provided two conditions are met:
  #   1. we haven't already added a path for that node
  #   2. the generator still has some juice left
  #
  # Remember: we already know this graph is going to be connected, so we
  # don't have to worry about revisiting nodes in case we can suddenly reach them
  visited   = Set.new
  flows     = Hash.new {|h, k| h[k] = 0 }
  remainder = grid.generators.map {|g| [g, g.power - g.node.load] }.to_h

  neighbors.sort_by {|n, g, p| p.size }.each do |node, gen, path|
    next if visited.include? node
    next if remainder[gen] < node.load

    remainder[gen] -= node.load
    path.each {|e| flows[e] += 1 }
  end

  #flows = {}
  #nearest_nodes.each.with_index do |(g, ns), i|
  #  cg = ConnectedGraph.new ns
  #  cg.traverse_edges g.node do |edge, from, to|
  #    flows[edge] = edge.flow(:from => from, :restrict => cg.nodes)
  #  end
  #end

  max, min = flows.values.max, flows.values.min
  quints = 5.times.map {|i| (max - min) * i / 5.0 + min }
  puts "\t[max, min]: #{[max, min]}"
  puts "\tquints: #{quints}"

  percentile_80 = flows.filter {|e, f| f > quints[4] }.map {|e, f| e }
  percentile_60 = flows.filter {|e, f| f > quints[3] && f < quints[4] }.map {|e, f| e }
  percentile_40 = flows.filter {|e, f| f > quints[2] && f < quints[3] }.map {|e, f| e }
  percentile_20 = flows.filter {|e, f| f > quints[1] && f < quints[2] }.map {|e, f| e }
  percentile_00 = flows.filter {|e, f| f > quints[0] && f < quints[1] }.map {|e, f| e }

  puts "\tReachable edges: #{flows.size}"
  puts "\t80-100%: #{percentile_80.size}"
  puts "\t60-80%:  #{percentile_60.size}"
  puts "\t40-60%:  #{percentile_40.size}"
  puts "\t20-40%:  #{percentile_20.size}"
  puts "\t 0-20%:  #{percentile_00.size}"

  plot_grid grid

  plot_edges percentile_80, :color => REDS[5]
  plot_edges percentile_60, :color => REDS[4]
  plot_edges percentile_40, :color => REDS[3]
  plot_edges percentile_20, :color => REDS[1]
  plot_edges percentile_00, :color => REDS[0]
  show_plot

  puts "\tUnreachable: #{grid.unreached.size}"
end

# IDEA
#
# Minimum spanning tree to construct the grid
# Then:
#   pick the median node (same # of edges on all branches)
#     find longest edge, pick median node
#   pick the n/3 nodes (???) such that each root has roughly the same number of nodes closest to it
#   k-means
#     cluster by geographic distance
#     cluster by edges on MST
#
# Then:
#   Put generators at geographic centroids of clusters
#     then build new edges
#   Put generators at nodal centroids of clusters
#   Put generators at *intersections* between clusters
#
# Questions:
#   How do I get clusters that overlap, so that each node has some kind of backup source?
#     Deal with resiliency later. Although overlapping clusters is a good question
#
# Assign generators based on an MST
# Assign redundancy by making a maximally connected graph, and then remove
#   edges according to some algorithm


############################

#plot_grid grid
#show_plot

puts
puts "Grid:"
puts "\t# of generators: #{grid.generators.size}"
puts "\tPower of generators: #{grid.generators.sum {|g| g.power }}"
puts "\tPower required: #{grid.nodes.size}"
efficiency = grid.reach.load / grid.power.to_f
puts "\tEfficiency: #{efficiency}"
puts "\tUnreached: #{grid.unreached.size}"

#require 'pry'
#binding.pry


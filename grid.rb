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
end

grid, nodes, edges = nil
PRNG = Random.new 1138
$parallel = opts[:parallel]
$elapsed = 0

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
  puts "\tUnreachable: #{grid.unreached.size}"
end

# This one is dangerous because it will render the graph as cyclic.
# Goodbye acyclic graph. I wonder what algorithms will no longer work?
time "Adding new generators via construction of new lines" do

end

time "Adding new generators via on-premises construction" do
  new_gens = 0
  more_power = 0

  # This is the process we would iterate

  # Split the graph into its connected subgraphs
  # Have to split into connected components and cluster those individually
  # Because otherwise we're trying to cluster an unconnected graph using a
  # distance formula that requires them to be connected
  connected_graphs = grid.unreached.connected_subgraphs

  # Which generators need more power to get small nearby clusters?

  # Find out which clusters are attached to other clusters.
  associations = connected_graphs.map do |cg|
    neighbors = grid.generators.filter {|g| cg.touching g.reach }

    [cg, neighbors]
  end

  # Is it worth increasing the power output of a generator? Or do we need to
  # build a new one entirely?
  #   o  find first suitable neighbor
  #   o  if neighbor is enlargeable and we're not too big, join neighbor
  #   o  if no neighbor is enlargeable, build new generator
  associations.each do |connected_graph, neighbors|
    added = false
    gen = nil

    # Only going to join enlargeable neighbors
    neighbors.filter {|n| n.enlargeable? }.each do |neighbor|
      # If we are less than 20% of the size of the neighbor,
      # let's join them
      if connected_graph.size.to_f / neighbor.reach.size < 0.2
        neighbor.power += connected_graph.demand
        neighbor.calculate_reach!

        puts "\tincreased power by #{connected_graph.demand}"

        added = true
        more_power += 1
        gen = neighbor
        break
      end
    end

    # If no neighbor is enlargeable, build new generator
    if added == false
      max_allowed_power = [connected_graph.demand, 100].min
      # We're building a generator, but only for what we need
      grid.generators << Generator.new(grid.graph,
                                       connected_graph.site_on_premises,
                                       max_allowed_power)
      gen = grid.generators.last
      new_gens += 1

      plot_graph connected_graph
      plot_generator gen
      show_plot
    end
  end

  puts "\tNew generators: #{new_gens}"
  puts "\tIncreased power: #{more_power}"
  puts "\tUnreachable: #{grid.unreached.size}"

  connected_graphs = grid.unreached.connected_subgraphs
  puts "\t\tSubgraph sizes: #{connected_graphs.map {|cg| cg.size }.inspect}"
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

plot_grid grid
show_plot

p grid.generators.map {|g| g.power }

puts
puts "Grid:"
puts "\t# of generators: #{grid.generators.size}"
puts "\tPower of generators: #{grid.generators.sum {|g| g.power }}"
puts "\tPower required: #{grid.nodes.size}"
puts "\tEfficiency: #{grid.nodes.size.to_f / grid.generators.sum {|g| g.power }}"
puts "\tUnreached: #{grid.unreached.size}"

require 'pry'
binding.pry


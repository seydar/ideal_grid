#!/usr/bin/env ruby
require 'optimist'
require_relative '../electric_avenue.rb'

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

  opt :nodes, "Number of nodes in the grid", :type => :integer, :default => 100
  opt :clusters, "How many nodes per generator", :type => :integer, :default => 10
  opt :intermediate, "Show intermediate graphics of flow calculation", :type => :integer
  opt :reduce, "How many times should we try to reduce congestion", :type => :integer, :default => 1
end

grid, nodes, edges = nil
$elapsed = 0
$intermediate = opts[:intermediate]

time "Edge production" do

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

  puts "\t#{opts[:nodes]} nodes"
  puts "\t#{edges.size} edges in complete graph"
end

$nodes = nodes
update_ranges $nodes

time "Tree production" do
  mst = []

  # Builds edges between nodes according to the MST
  parallel_filter_kruskal edges, UnionF.new(nodes), mst

  $algorithm = "Kruskal (since edges are too few)" if edges.size <= SEQ_THRESHOLD
  puts "Using #{$algorithm}"
  puts "\t#{mst.size} edges in MST"

  # Give edges new IDs so that they are 0..|edges|
  edges = nodes.map(&:edges).flatten.uniq
  edges.each.with_index {|e, i| e.id = i }
end

time "Add initial generators [#{opts[:clusters]} nodes/generator]" do

  grid = Grid.new nodes, []

  graph = ConnectedGraph.new nodes

  # Needed for the global adjacency matrix for doing faster manhattan distance
  # calculations
  KMeansClusterer::Distance.graph = graph
  
  grid.build_generators_for_unreached opts[:clusters]

  puts grid.info
end

time "Adding new generators via clustering" do
  connected_graphs = grid.unreached.connected_subgraphs
  puts ("\tUnreached: #{grid.unreached.size} " +
        "(#{connected_graphs.size} subgraphs)")
  puts "\t\t#{connected_graphs.map {|cg| cg.size }}"

  built = grid.build_generators_for_unreached opts[:clusters]
  grown = grid.grow_generators_for_unreached

  puts "\tBuilt: #{built}"
  puts "\tGrown: #{grown}"

  grown = grid.grow_generators_for_unreached
  puts "\tGrown: #{grown}"

  puts grid.info
end

time "Calculate flow" do 

  grid.calculate_flows! # redundant; already done in `#grow_generators_for_unreached`

  puts grid.flow_info

  plot_flows grid, :n => 100
  show_plot
end

time "Reduce congestion" do

  added = []
  opts[:reduce].times do |i|
    new_edges = grid.reduce_congestion

    # TODO Are certain edges more effective than others? How do we know?
    added << []
    new_edges.each do |src, tgt, edge, dist|
      if edge.length < 0.5
        added[-1] << edge
        edge.mark_nodes!
      end
    end

    grid.reset!

    puts grid.flow_info
    puts grid.info

    added[-1].each do |edge|
      edge.detach! if grid.flows[edge] == 0
    end

    qual    = added[-1].size
    no_flow = added[-1].count {|e| grid.flows[e] == 0 }

    puts "\tQualifying edges: #{qual}"
    puts "\tNo-flow edges: #{no_flow}"
    puts "\tNew edges: #{qual - no_flow}"
  end

  plot_flows grid, :n => 10, :focus => :unreached
  plot_edges added.flatten, :color => "green", :width => 3
  show_plot
end

g2 = nil
time "Fresh map", :run => false do
  # Edges are preserved — now we're going to see about placing the
  # generators elsewhere
  g2 = Grid.new grid.nodes, []
  g2.build_generators_for_unreached opts[:clusters]
  g2.grow_generators_for_unreached
  g2.build_generators_for_unreached opts[:clusters]
  g2.grow_generators_for_unreached

  puts g2.flow_info
  puts g2.info

  plot_flows g2, :n => 10
  show_plot
end

############################

#require 'pry'
#binding.pry


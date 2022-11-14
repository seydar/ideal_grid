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
  opt :intermediate, "Show intermediate graphics of flow calculation", :type => :integer
end

grid, nodes, edges, flows = nil
PRNG = Random.new 1138
$parallel = opts[:parallel]
$elapsed = 0
$intermediate = opts[:intermediate]


puts "parallel: #{$parallel}"
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

def circle(nodes)
  nodes.size.times do |i|
    e = Edge.new nodes[i],
                 nodes[(i + 1) % nodes.size],
                 nodes[i].euclidean_distance(nodes[(i + 1) % nodes.size])
    nodes[i].edges << e
    nodes[(i + 1) % nodes.size].edges << e
  end
end

  mst = []
time "Tree production" do

  # Builds edges between nodes according to the MST
  parallel_filter_kruskal edges, UnionF.new(nodes), mst

  $algorithm = "Kruskal (since edges are too few)" if edges.size <= SEQ_THRESHOLD
  puts "Using #{$algorithm}"
  puts "\t#{mst.size} edges in MST"
end

time "Add initial generators [#{opts[:clusters]} nodes/generator]" do

  grid = Grid.new nodes, []

  # Keep generators an array of arrays so we can track which generators were built
  # after which iteration
  graph = ConnectedGraph.new nodes

  # Needed for the global adjacency matrix for doing faster manhattan distance
  # calculations
  KMeansPP.graph = graph
  
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
end

plot_flows grid, :n => 10
show_plot

added = []
time "Reduce congestion" do

  # How do I find the generators that have the heaviest flows?

  5.times do |i|
    groupings = grid.graph.nodes.group_by {|n| grid.nearest_generator n }
    stressed_gens = groupings.keys.sort_by do |gen|
      ns = groupings[gen]
      es = ns.map {|n| n.edges }.flatten.uniq
      es.sum {|e| grid.flows[e] }
    end

    gen_factors = grid.generators.combination(2).map do |g1, g2|
      delta_position = (stressed_gens.index(g1) - stressed_gens.index(g2)).abs
      [g1,
       g2,
       delta_position /
         g1.node.euclidean_distance(g2.node)]
    end.sort_by {|_, _, v| -v }

    # get the first pair that contains the overloaded generator
    pair = gen_factors[i]

    puts "\tConnecting the group around #{pair[0].node.to_a} to #{pair[1].node.to_a}"
    added << grid.connect_graphs(pair[0], pair[1])

    grid.reset!

    puts grid.flow_info
    puts grid.info
  end
end

plot_flows grid, :n => 10
plot_edges added, :color => "yellow", :width => 3
show_plot

g2 = nil
time "Fresh map" do
  g2 = Grid.new grid.nodes, []
  g2.build_generators_for_unreached opts[:clusters]
  g2.grow_generators_for_unreached
  g2.build_generators_for_unreached opts[:clusters]
  g2.grow_generators_for_unreached

  puts g2.flow_info
  puts g2.info
end

plot_flows g2, :n => 10
show_plot

############################

#plot_grid grid, :reached
#show_plot
#
#plot_grid grid, :unreached
#show_plot

puts
puts "Grid:"
puts grid.info

#require 'pry'
#binding.pry


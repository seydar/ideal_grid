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

  mst = []
time "Tree production" do


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

  grid.calculate_flows!
  puts "\tGenerators: #{grid.generators.size}"
  puts "\t\t#{grid.generators.map {|g| g.power }}"
  puts "\tUnreached: #{grid.unreached.size} " +
       "(#{grid.unreached.connected_subgraphs.size} subgraphs)"
end

time "Adding new generators via clustering" do
  connected_graphs = grid.unreached.connected_subgraphs
  puts "\tUnreached subgraph sizes: #{connected_graphs.map {|cg| cg.size }.inspect}"

  built = grid.build_generators_for_unreached opts[:clusters]
  grown = grid.grow_generators_for_unreached

  puts "\tBuilt: #{built}"
  puts "\tGrown: #{grown}"
  puts "\tGenerators: #{grid.generators.size}"
  puts "\t\t#{grid.generators.map {|g| g.power }}"
  puts "\tUnreached: #{grid.unreached.size} " +
       "(#{grid.unreached.connected_subgraphs.size} subgraphs)"
end

time "Adding new generators via clustering" do
  connected_graphs = grid.unreached.connected_subgraphs
  puts "\tUnreached subgraph sizes: #{connected_graphs.map {|cg| cg.size }.inspect}"

  built = grid.build_generators_for_unreached opts[:clusters]
  grown = grid.grow_generators_for_unreached

  puts "\tBuilt: #{built}"
  puts "\tGrown: #{grown}"
  puts "\tGenerators: #{grid.generators.size}"
  puts "\t\t#{grid.generators.map {|g| g.power }}"
  puts "\tUnreached: #{grid.unreached.size} " +
       "(#{grid.unreached.connected_subgraphs.size} subgraphs)"
end

untread = nil
time "Calculate flow" do 

  grid.calculate_flows!

  flowing_edges = grid.flows.keys
  untread = mst - flowing_edges

  puts grid.flow_info
end

plot_flows grid, :n => 10
plot_edges untread, :color => "cyan"
show_plot

#time "Reduce congestion" do
#
#  congested = grid.flows.sort_by {|e, f| -f } # max first
#  unused    = edges - grid.flows.keys # these are possible shunts; unused edges
#
#  # `unused` is the rest of the complete graph, so anything we could possibly
#  # dream of is in it, which means we have to be very judicious and specific
#  # about which edge we want from it.
#  #
#  # But for now, let's just fuck around and see what happens
#  #max_gen = grid.generators.max_by {|g| g.power }
#  #edge = unused.filter {|e| e.nodes.include? max_gen.node }.sample
#  #edge = unused.filter {|e| e.nodes.include? grid.unreached.nodes[0] }.sample
#  #edge = unused.sample
#  #edges = unused.sort_by {|e| e.length }[0..10]
#  #cong_nodes  = congested[0..20].map {|e, f| e.nodes }.flatten
#  #needs_shunt = cong_nodes.sort_by {|n| n.edges.size }[0..10]
#  #edges = unused.filter {|e| (e.nodes - needs_shunt).size == 1 }[0..10]
#
#  #edges.each {|e| e.mark_nodes! }
#  edge = edges.find do |e|
#    e.nodes.include?(nodes[279]) &&
#    e.nodes.include?(nodes[778])
#  end
#  edge.mark_nodes!
#
#  grid.reset!
#
#  flowing_edges = grid.flows.keys
#  untread = mst - flowing_edges
#
#  puts grid.flow_info
#end
#
#plot_flows grid, :n => 10
#plot_edges untread, :color => "cyan"
#show_plot

############################

#plot_grid grid, :reached
#show_plot
#
#plot_grid grid, :unreached
#show_plot

puts
puts "Grid:"
puts "\t# of generators: #{grid.generators.size}"
puts "\tPower of generators: #{grid.generators.sum {|g| g.power }}"
puts "\tPower required: #{grid.nodes.size}"
efficiency = grid.reach.load / grid.power.to_f
puts "\tEfficiency: #{efficiency}"
puts "\tReached: #{grid.reach.size}"
puts "\tUnreached: #{grid.unreached.size} " +
     "(#{grid.unreached.connected_subgraphs.size} subgraphs)"

#require 'pry'
#binding.pry


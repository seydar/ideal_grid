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
  opt :reduce, "How many times should we try to reduce congestion", :type => :integer, :default => 1
  opt :quiet, "Don't show the graphs", :type => :boolean
  opt :parallel, "How many cores to use", :type => :integer, :default => 4
end

grid, nodes, edges = nil
$elapsed  = 0
$parallel = opts[:parallel] <= 1 ? false : opts[:parallel]

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
  built = [] #grid.build_generators_for_unreached opts[:clusters]
  grown = grid.grow_generators_for_unreached

  puts "\tBuilt: #{built}"
  puts "\tGrown: #{grown}"

  grown = grid.grow_generators_for_unreached
  puts "\tGrown: #{grown}"

  puts grid.info
end

time "Calculate flow" do 

  # 0.12s on 1000 nodes and 13 generators
  grid.calculate_flows! # redundant; already done in `#grow_generators_for_unreached`

  puts grid.flow_info

  plot_flows grid, :n => 100
  show_plot unless opts[:quiet]
end

time "Drakos resiliency on the base grid", :run => false do
  drak = grid.resiliency :drakos, 0.4
  puts "\tDrakos: #{drak}"
end

time "Reduce congestion" do

  new_edges = grid.reduce_congestion

  sorting_info = new_edges.map do |src, tgt, edge, dist|
    if edge.length < 0.5
      edge.attach!
      grid.reset!
      edge.detach!

      [edge, grid.flows[edge], grid.transmission_loss[1]]
    end
  end.compact

  puts "\tEdge info:"
  # maximize flow, minimize distance
  ranked = sorting_info.sort_by {|e, f| f / e.length }
  added  = ranked[(0.75 * ranked.size).to_i..-1].reverse.map do |e, f, l|
    puts "\t\tRank: #{(f / e.length).round(2)}, Length: #{e.length.round(2)}, Flow: #{f.round(2)}, Tx loss: #{l.round(2)}"

    e.attach!
    e
  end

  grid.reset!

  puts grid.flow_info
  puts grid.info

  qual = new_edges.size
  t_l  = added.sum(&:length)

  puts "\tQualifying edges: #{qual}"
  puts "\tLow-flow edges: #{qual - added.size}"
  puts "\tNew edges: #{added.size} (total length: #{t_l}) "

  plot_flows grid, :n => 10
  plot_edges added, :color => "green", :width => 3
  show_plot unless opts[:quiet]
end

# Estrada takes too long
time "Drakos resiliency on the new grid", :run => false do
  #profile do
    drak = grid.resiliency :drakos, 0.4
    puts "\tDrakos: #{drak}"
  #end
end

############################

#require 'irb'
#IRB.start


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
  opt :edges, "Max number of edges to build", :type => :integer, :default => 4
  opt :percentiles, "Which percentiles to pull from (low..high)", :type => :string, :default => "5..8"
end

grid, nodes, edges = nil
$elapsed  = 0
$parallel = opts[:parallel] <= 1 ? false : opts[:parallel]
opts[:percentiles] = Range.new(*opts[:percentiles].split("..").map(&:to_i))

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

time "Drakos resiliency on the base grid" do
  drak = grid.resiliency :drakos, 0.4
  puts "\tDrakos: #{drak}"
end

time "Reduce congestion" do

  puts "\tPercentiles: #{opts[:percentiles]}"
  new_edges = grid.reduce_congestion opts[:percentiles]

  # Hard ceiling on the edge length
  candidates = new_edges.map {|_, _, e, _| e.length < 0.5 ? e : nil }.compact

  # potentially thousands of trials to run
  # We're only interested in building up to 4 edges here, since we're trying
  # to show bang for buck
  trials = (1..opts[:edges]).map {|i| candidates.combination(i).to_a }.flatten(1)

  puts "\tMax # of edges to build: #{opts[:edges]}"
  puts "\t#{candidates.size} candidates, #{trials.size} trials"

  # Test out each combination.
  # Detaching the edges in another process is unnecessary since the grid object
  # is copied (and thus the main processes's grid is unaffected), but the code is
  # included because it's cheap and is required for single-threaded ops
  results = trials.parallel_map do |cands|
    cands.each {|e, _, _| e.attach! }
    grid.reset!
    cands.each {|e, _, _| e.detach! }

    grid.transmission_loss[1]
  end
  results = trials.zip results

  # minimize tx loss, minimize total edge length
  ranked = results.sort_by do |cs, l|
    l ** 1.35 + l * cs.sum(&:length)
  end

  puts "\tTop 10 trials:"
  ranked[0..10].map do |cs, l|
    puts "\t\t# of Edges: #{cs.size}, " +
         "Length: #{cs.sum(&:length).round(2)}, " +
         "Tx loss: #{l.round(2)}%"
  end

  added = ranked[0][0]
  added.each {|e| e.attach! }

  grid.reset!

  puts grid.flow_info
  puts grid.info

  puts "\tQualifying edges: #{candidates.size}"
  puts "\tNew edges: #{added.size}"
  puts "\tTotal length: #{added.sum(&:length).round 2}"

  plot_flows grid, :n => 10
  plot_edges added, :color => "green", :width => 3
  show_plot unless opts[:quiet]
end

# Estrada takes too long
time "Drakos resiliency on the new grid" do
  #profile do
    drak = grid.resiliency :drakos, 0.4
    puts "\tDrakos: #{drak}"
  #end
  
  require 'pry'
  binding.pry
end

############################

#require 'irb'
#IRB.start


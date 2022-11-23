#!/usr/bin/env ruby
require 'gnuplot'
require 'optimist'
require_relative 'kmeans-clusterer.rb'
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
  opt :clusters, "How many nodes per generator", :type => :integer, :default => 10
  opt :intermediate, "Show intermediate graphics of flow calculation", :type => :integer
  opt :reduce, "How many times should we try to reduce congestion", :type => :integer, :default => 1
end

grid, nodes, edges = nil
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
end

plot_flows grid, :n => 10
show_plot

added = []
time "Reduce congestion" do

  # How do I find the generators that have the heaviest flows?

  opts[:reduce].times do |i|
    grouped_flows   = grid.flows.group_by {|e, f| f }
    group_keys      = grouped_flows.keys.sort

    low_flows  = group_keys[0..group_keys.size / 5].map {|k| grouped_flows[k] }.flatten 1
    high_flows = group_keys[-(group_keys.size / 5)..-1].map {|k| grouped_flows[k] }.flatten 1

    h_es = high_flows.map {|e, f| e }
    l_es = low_flows.map {|e, f| e }

    #plot_flows grid
    #plot_edges h_es, :color => "yellow"
    #plot_edges l_es, :color => "green"
    #show_plot

    nodes = (h_es + l_es).map {|e| e.nodes }.flatten.uniq
    disjoint = DisjointGraph.new nodes

    cgs = disjoint.connected_subgraphs.map do |cg|
      [cg, cg.edges.sum {|e| grid.flows[e] }]
    end

    #plot_flows grid
    #cgs.each {|cg, _| plot_edges cg.edges, :color => "green" }
    #show_plot


    scores = cgs.combination(2).map do |(cg1, cg1_sum), (cg2, cg2_sum)|
      [cg1,
       cg2,
       (cg1_sum - cg2_sum).abs * grid.group_distance(cg1, cg2) /
         grid.connect_graphs(cg1, cg2).length
      ]
    end.sort_by {|_, _, v| -v }

    pair = scores[0]

    # TODO god this whole thing is ugly
    unless pair
      puts "\tNo subgraphs to connect; all flows are even"
      return
    end

    puts "\tConnecting the group around #{pair[0].inspect} to #{pair[1].inspect}"
    e = grid.connect_graphs(pair[0], pair[1])
    if e
      added << e
      e.mark_nodes!
    end

    grid.reset!

    puts grid.flow_info
    puts grid.info
  end
end

plot_flows grid, :n => 10
plot_edges added, :color => "green", :width => 3
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

#require 'pry'
#binding.pry


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

  opt :nodes, "Number of nodes in the grid", :type => :integer, :default => 100
  opt :clusters, "How many nodes per generator", :type => :integer, :default => 10
  opt :intermediate, "Show intermediate graphics of flow calculation", :type => :integer
  opt :reduce, "How many times should we try to reduce congestion", :type => :integer, :default => 1
end

grid, nodes, edges = nil
PRNG = Random.new 1138
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

exit

added = []
time "Reduce congestion", run: false do

  # How do I find the generators that have the heaviest flows?

  opts[:reduce].times do |i|
    grouped_flows   = grid.flows.group_by {|e, f| f }
    group_keys      = grouped_flows.keys.sort

    # Okay. Find the sources. The sources have to be *individual edges*, or
    # else we defeat the purpose of reducing the flow down those edges.
    # This isn't entirely true, but it's close enough for now.
    #
    # Options for sources:
    #   1. Build new edge that connects to a node on a high-flow edge
    #   2. Increase the load on a low-flow edge that already connects to a
    #      high-flow edge
    #
    #   (#2 feels like a general case of #1)
    #
    # Options for destinations:
    #   1. Connect the source to a low-flow CG.
    #      dafuq does this mean. Still an unsolved problem.
    #
    #      What does CG mean? Yes the CG is connected, but a graph of which
    #      nodes?
    #
    #      I think you can't just connect a high-flow edge to a random low-flow
    #      edge. There's a current (hah) of flow that is feeding a set of nodes,
    #      and if a generator now has to feed another region of nodes, then the
    #      original heavy current is unlikely to change (if the new region of
    #      nodes is too far away).
    #
    #      I need to basically create a circular connection so that heavy current
    #      gets a closer connection to the source.
    #
    # Nitpick: you don't connect an edge to an edge, you connect a node to a node
    # Yes, you connect edges, but in the interest of being deliberate with what
    # we do, we want to pick *nodes*.
    
    # Source; option 1
    max_edge, _ = grid.flows.max_by {|e, f| f }

    # Which is the node of the edge that touches the low-flow edge?
    # What if each node of the edge has multiple edges connecting to it?
    adj_edges = max_edge.nodes.map do |node|
      grid.graph.adjacencies[node] # [[node, edge]]
    end.flatten 1 # [[node, edge]]

    # There are only going to be two options for the nodes here, since our base
    # is `max_edge.nodes` up above. So this finds the edge that doesn't bear much
    # of the load.
    source, _ = adj_edges.max_by {|n, e| grid.flows[e] }
    s_cg = ConnectedGraph.new [source]
    
    ######

    low  = 3 * group_keys.size / 5
    high = 4 * group_keys.size / 5
    med_flows  = group_keys[low..high].map {|k| grouped_flows[k] }.flatten 1

    m_es = med_flows.map {|e, f| e }

    nodes = m_es.map {|e| e.nodes }.flatten.uniq
    disjoint = DisjointGraph.new nodes

    cgs = disjoint.connected_subgraphs.map do |cg|
      [cg, cg.edges.sum {|e| grid.flows[e] }]
    end


    plot_flows grid
    cgs.each {|cg, _| plot_edges cg.edges, :color => "green" }
    show_plot


    scores = [s_cg].product(cgs).map do |cg1, (cg2, cg2_sum)|
      [cg1,
       cg2,
       cg2_sum /
         grid.connect_graphs(cg1, cg2).length
      ]
    end.sort_by {|_, _, v| -v }

    pair = scores[i]

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


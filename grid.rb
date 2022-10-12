#!/usr/bin/env ruby
require 'gnuplot'
require 'optimist'
require './k_means_pp.rb'
require './plotting.rb'
require './monkey_patch.rb'
Dir['./lib/graph/*.rb'].each {|f| require f }
require './filter_kruskal.rb'

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
  opt :clusters, "Cluster the nodes into k clusters", :type => :integer, :default => 3
end

nodes, edges, clusters, generators, unreached = nil
unreached_cs, new_generators = nil
PRNG = Random.new 1337
$parallel = opts[:parallel]
opts[:clusters] = (opts[:nodes].to_f / 10).ceil

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

time "Tree production" do

  mst = []

  parallel_filter_kruskal edges, UnionF.new(nodes), mst

  puts "Using #{$algorithm}"
  puts "\t#{mst.size} edges in MST"
end

time "Node clustering [#{opts[:clusters]} clusters]" do

  conn_graph = ConnectedGraph.new nodes
  clusters = conn_graph.cluster opts[:clusters]

  generators = clusters.map do |cluster|
    Generator.new cluster, 10
  end
  
  generators.each do |generator|
    puts generator.info
  end

  unreached = DisjointGraph.new(nodes - generators.map {|g| g.reach[:nodes] }.flatten)

  # Split the graph into its connected subgraphs
  connected_graphs = unreached.connected_subgraphs
  puts "\tConnected graphs: #{connected_graphs.size}"

  # Have to split into connected components and cluster those individually
  # Because otherwise we're trying to cluster an unconnected graph using a
  # distance formula that requires them to be connected
  unreached_cs = connected_graphs.map do |cg|
    klusters = (cg.size / 10.0).ceil
    puts "producing clusters (#{cg.size} nodes, #{klusters} clusters)"
    cg.cluster klusters
  end.flatten 1

  new_generators = unreached_cs.map do |cluster|
    Generator.new cluster, 10
  end

  puts "\tGenerators: #{generators.size}"

  # TODO Which generators have leftover power to supply?
  # Which generators need more power to get small nearby clusters?

  # Find out which clusters are attached to other clusters.
  # Get their sizes.
  associations = unreached_cs.map do |cluster|
    assocs = clusters.filter do |kl|
      edge_nodes = cluster.points.map {|n| n.edges.map {|e| e.nodes } }.flatten
      kl.points & edge_nodes != []
    end
    [cluster.points.size, assocs.size]
  end

  pp associations

  # Is it worth increasing the power output of a generator? Or do we need to
  # build a new one entirely?
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

plot_clusters clusters
show_plot

plot_generators generators, nodes
show_plot

plot_generators new_generators, nodes
show_plot

#gets

#plot_clusters unreached_cs
#show_plot

#require 'pry'
#binding.pry


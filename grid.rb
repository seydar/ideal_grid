require 'gnuplot'
require './k_means_pp.rb'
require './plotting.rb'
require './monkey_patch.rb'
Dir['./lib/graph/*.rb'].each {|f| require f }
require './filter_kruskal.rb'

nodes, edges, clusters = nil
PRNG = Random.new 54

time "Edge production" do

  $parallel = !!ARGV[1]
  puts "parallel: #{$parallel}"

  # Generate a bunch of random points
  # We track IDs here so that equality can be asserted more easily after
  # objects have been copied due to parallelization (moving in and out of
  # processes -- they get marshalled and sent down a pipe)
  num   = ARGV[0] ? ARGV[0].to_i : 40
  nodes = num.times.map do |i|
    Node.new(10 * PRNG.rand, 10 * PRNG.rand, :id => i)
  end

  pairs = nodes.combination 2
  edges = pairs.map.with_index do |(p_1, p_2), i|
    Edge.new p_1,
             p_2,
             p_1.euclidean_distance(p_2),
             :id => i
  end

  puts "#{num} nodes"
  puts "\t#{edges.size} edges in complete graph"
end

time "Tree production" do

  mst = []

  #kruskal edges, UnionF.new(nodes)
  #qKruskal edges, UnionF.new(nodes), mst
  #filterKruskal edges, UnionF.new(nodes), mst
  if $parallel
    #parallel_filter_kruskal edges, UnionF.new(nodes), mst
    kruskal edges, UnionF.new(nodes), mst
  else
    kruskal edges, UnionF.new(nodes), mst
  end

  puts "Using #{$algorithm}"
  puts "\t#{mst.size} edges in MST"
end

time "Node clustering" do

  clusters = KMeansPP.clusters(nodes, 3) {|n| n.to_a }
end

# IDEA
#
# Minimum spanning tree to construct the grid
# Then:
#   pick the median node (same # of edges on all branches)
#     BFS until n/2 is reached?
#     then backtrack to latest edge with greatest number of nodes
#   pick the n/3 nodes (???) such that each root has roughly the same number of nodes closest to it
#   k-means
#     cluster by geographic distance
#     cluster by edges on MST
#
# Then:
#   Put generators at geographic centroids of clusters
#     then build new edges
#   Put generators at nodal centroids of clusters
#
# Questions:
#   How do I get clusters that overlap, so that each node has some kind of backup source?
#
# Assign generators based on an MST
# Assign redundancy by making a maximally connected graph, and then remove
#   edges according to some algorithm


############################

plot clusters

#require 'pry'
#binding.pry


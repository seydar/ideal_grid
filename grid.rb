require 'math'
require 'set'
require 'gnuplot'
require './k_means_pp.rb'
require './plotting.rb'
require './monkey_patch.rb'
Dir['./lib/graph/*.rb'].each {|f| require f }
require './filter_kruskal.rb'

# Kruskal's algorithm for an MST
# https://github.com/mneedham/algorithms2/blob/master/kruskals.rb
def has_cycles(edge, mst)
  node_1, node_2 = *edge.nodes
  mst.each {|x| x.explored = false }
  cycle_between node_1, node_2, mst
end

def cycle_between(one, two, edges)
  adjacent_edges = edges.filter {|e| e.nodes.include? one }
  return false if adjacent_edges.empty?

  adjacent_edges.select {|e| not e.explored }.each do |edge|
    edge.explored = true
    other = edge.nodes.find {|n| n != one } # `edge.nodes.size == 2`

    return true if other == two || cycle_between(other, two, edges)
  end

  false
end

nodes, edges, clusters, mst = nil
PRNG = Random.new 54
time "Edge production" do

  # Generate a bunch of random points
  num   = ARGV[0] ? ARGV[0].to_i : 40
  nodes = num.times.map { Node.new(10 * PRNG.rand, 10 * PRNG.rand) }
  
  pairs = nodes.combination 2
  edges = pairs.map {|p_1, p_2| Edge.new p_1,
                                         p_2,
                                         p_1.euclidean_distance(p_2) }
end

time "Tree production" do

  p edges.size

  qKruskal edges, UnionF.new(nodes)
  #kruskal edges
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


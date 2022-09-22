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

nodes, edges, clusters = nil
PRNG = Random.new
$parallel = opts[:parallel]

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

time "Node clustering [#{opts[:clusters]} clusters]" do

  clusters = KMeansPP.clusters(nodes, opts[:clusters]) {|n| n.to_a }
end

time "Effective currents" do

  generators = clusters.map do |cluster|
    Generator.new cluster
  end
  
  generators.each do |generator|
    puts "\tCluster #{generator.cluster.centroid.original.inspect}"
    time("\t\tCalculated flow") { print "\t\t\t"; p generator.flow }
    time("\t\tLoop flow") { print "\t\t\t"; p generator.flow_loop }
    puts "\t\tTotal line length: #{generator.demand}"
    puts "\t\tTotal nodes: #{generator.cluster.points.size}"
  end
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

plot clusters

#require 'pry'
#binding.pry


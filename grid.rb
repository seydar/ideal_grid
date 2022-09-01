require 'math'
require 'gnuplot'
require './kmeans-clusterer.rb'

class Point
  attr_accessor :x
  attr_accessor :y
  attr_accessor :visited
  attr_accessor :edges

  def initialize(x, y)
    @x, @y = x, y
    @edges = []
  end

  def inspect
    "#<Point: @x=#{x}, @y=#{y}, # of edges=#{edges.size}>"
  end

  def other_nodes_connected_to_not(except)
    branches = edges - [except]
    branches.map do |b|
      (b.nodes - [self])[0].other_nodes_connected_to_not b
    end.sum + 1
  end

  def dist(p_2)
    Math.sqrt((self.x - p_2.x) ** 2 + (self.y - p_2.y) ** 2)
  end

  def to_a
    [x, y]
  end
end

class Edge
  attr_accessor :nodes # guaranteed to be #size == 2
  attr_accessor :weight
  attr_accessor :explored

  def initialize(to, from, weight=0)
    @weight = weight
    @nodes  = [to, from]
  end

  def mark_nodes!
    nodes.each {|n| n.edges << self }
  end
end

# Kruskal's algorithm for an MST
# https://github.com/mneedham/algorithms2/blob/master/kruskals.rb
def has_cycles(edge)
  node_1, node_2 = *edge.nodes
  @minimum_spanning_tree.each {|x| x.explored = false }
  cycle_between node_1, node_2, @minimum_spanning_tree
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

# TODO add a graph class and add dijkstra's algorithm to it

# Generate a bunch of random points
points = 10.times.map { Point.new(10 * rand, 10 * rand) }
edges  = points.combination(2).map {|p_1, p_2| Edge.new p_1,
                                                        p_2,
                                                        p_1.dist(p_2) }

@minimum_spanning_tree = []
edges.sort_by {|e| e.weight }.each do |edge|
  @minimum_spanning_tree << edge && edge.mark_nodes! unless has_cycles edge
end

kmeans = KMeansClusterer.run 3, points.map(&:to_a)

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


############################

def buffered_range(points, buffer=0.1)
  max = points.max
  min = points.min
  range = max - min
  buffer = range * buffer
  "[#{min - buffer}:#{max + buffer}]"
end

Gnuplot.open do |gp|
  Gnuplot::Plot.new gp do |plot|

    plot.xrange buffered_range(points.map {|p| p.x }, 0.2)
    plot.yrange buffered_range(points.map {|p| p.y }, 0.2)

    xs, ys = points.map {|p| p.x }, points.map {|p| p.y }
    plot.data << Gnuplot::DataSet.new([xs, ys])

    plot.data += @minimum_spanning_tree.map do |edge|
      xs = edge.nodes.map(&:x)
      ys = edge.nodes.map(&:y)

      Gnuplot::DataSet.new([xs, ys]) do |ds|
        ds.with = 'lines'
        ds.notitle
        ds.linecolor = "-1"
      end
    end

    colors = kmeans.clusters.zip(["red", "blue", "yellow", "magenta"]).to_h

    plot.data += kmeans.clusters.map do |cluster|
      xs = cluster.points.map {|p| p[0] }
      ys = cluster.points.map {|p| p[1] }

      Gnuplot::DataSet.new([xs, ys]) do |ds|
        ds.with = 'points pointtype 6'
        ds.notitle
        ds.linecolor = "rgb \"#{colors[cluster]}\""
      end
    end

    plot.data += kmeans.clusters.map do |cluster|
      xs = [cluster.centroid[0]]
      ys = [cluster.centroid[1]]

      Gnuplot::DataSet.new([xs, ys]) do |ds|
        ds.with = 'points pointtype 6 pointsize 3'
        ds.notitle
        ds.linecolor = 'rgb "orange"'
      end
    end

  end
end

#require 'pry'
#binding.pry


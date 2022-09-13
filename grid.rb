require 'math'
require 'set'
require 'gnuplot'
require './k_means_pp.rb'
require './plotting.rb'

class Graph
  attr_accessor :nodes
  attr_accessor :adjacencies

  # Need to specify the nodes, and then restrict the edges to only those
  # that connect to these nodes
  def initialize(nodes)
    raise "nodes cannot be empty" if nodes.empty?
    @nodes = nodes
    @adjacencies = {}

    fill_adjacencies!
  end

  # god damn this is ugly
  def fill_adjacencies!
    nodes.each do |node|

      adjacencies[node]  = []
      node.edges.each do |edge|
        other = edge.not_node node

        # We use the weight later one, so we might as well store it here
        # The `if` statement here is because these nodes are otherwise
        # completely connected, so we want to make sure that this graph is
        # restricted to the subset of nodes that we pass in.
        #
        # You are correct in thinking that I did not myself remember this
        # for many hours.
        adjacencies[node] << [other, edge.weight] if nodes.include? other
      end
    end
  end

  # Should these paths be remembered?
  def longest_path_from(source)
    visited  = Set.new
    distance = Hash.new {|h, k| h[k] = -1 }

    distance[source] = 0

    # Probably should replace this with a deque
    queue = []
    queue   << source
    visited << source

    until queue.empty?
      front = queue.shift

      adjacencies[front].each do |node, weight|
        unless visited.include? node
          distance[node] = distance[front] + weight
          queue   << node
          visited << node
        end
      end
    end

    distance.max_by {|k, v| v }
  end

  def longest_path
    node,  dist = longest_path_from nodes[0]
    start, dist = longest_path_from node

    Path.build start.path_to(node)
  end

  def longest_path2
    paths = nodes.combination(2).map {|n1, n2| n1.path_to n2 }
    max   = paths.max_by {|p| p.size }
    Path.build max
  end
end

class Path
  attr_accessor :edges
  attr_accessor :nodes

  def self.build(edges)
    path = new edges
    path.sort_points!

    path
  end

  def weight
    edges.map {|e| e.weight }.sum
  end

  def initialize(edges)
    @edges = edges
    @nodes = []
  end

  def sort_points!
    sorted = []

    if edges.size == 1
      @nodes = edges[0].nodes
      return
    end

    edges.each.with_index do |edge, i|
      if edges[i + 1]
        unique = edge.nodes - edges[i + 1].nodes # unique node to `edge`
        sorted << unique[0]
      else # we're at the last one
        unique = edge.nodes - edges[i - 1].nodes
        sorted << (edge.nodes - unique)[0]
        sorted << unique[0]
      end
    end

    @nodes = sorted
  end

  # Median by the number of edges, but not by weight
  # n edges, n + 1 nodes
  def median
    #nodes[nodes.size / 2]
    total = 0
    edges.each.with_index do |edge, i|
      total += edge.weight
      return nodes[i + 1] if total > weight / 2.0
    end

    raise "something went wrong in calculating the median"
  end

  def size
    edges.inject(0) {|s, e| s + e.weight }
  end
  alias_method :length, :size
end

class Node
  attr_accessor :x
  attr_accessor :y
  attr_accessor :visited
  attr_accessor :edges

  def initialize(x, y)
    @x, @y = x, y
    @edges = []
  end

  def inspect
    "#<Node: @x=#{x.round 3}, @y=#{y.round 3}, # of edges=#{edges.size}>"
  end

  def other_nodes_connected_to_not(except)
    branches = edges - [except]
    branches.map do |b|
      (b.nodes - [self])[0].other_nodes_connected_to_not b
    end.sum + 1
  end

  def euclidean_distance(p_2)
    Math.sqrt((self.x - p_2.x) ** 2 + (self.y - p_2.y) ** 2)
  end

  # No guarantee that path is shortest
  # Actually, we *are* guaranteed that because we're using a MST
  def path_to(p_2, prev=nil)
    edges.each do |edge|
      # Don't go back the way we came
      next if edge == prev

      if edge.not_node(self) == p_2
        return [edge]
      else
        path = edge.not_node(self).path_to p_2, edge
        return (path << edge) unless path.empty?
      end
    end

    []
  end

  def edge_distance(other)
    Path.build(path_to(other)).weight
  end

  def dist(p_2, style=:euclidean)
    case style
    when :edges
      edge_distance p_2
    when :euclidean
      euclidean_distance p_2
    else
      raise "No style provided for distance calculation"
    end
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

  def other_node(node)
    (nodes - [node])[0]
  end
  alias_method :not_node, :other_node

  def inspect
    n1 = nodes[0].to_a.map {|v| v.round 3 }
    n2 = nodes[1].to_a.map {|v| v.round 3 }
    "#<Edge: #{n1} <=> #{n2}>"
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
nodes = 40.times.map { Node.new(10 * rand, 10 * rand) }
edges = nodes.combination(2).map {|p_1, p_2| Edge.new p_1,
                                                      p_2,
                                                      p_1.euclidean_distance(p_2) }

@minimum_spanning_tree = []
edges.sort_by {|e| e.weight }.each do |edge|
  @minimum_spanning_tree << edge && edge.mark_nodes! unless has_cycles edge
end

clusters = KMeansPP.clusters(nodes, 3) {|n| n.to_a }

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


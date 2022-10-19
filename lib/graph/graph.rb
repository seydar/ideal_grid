require 'set'
require_relative "../siting.rb"

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

  def fill_adjacencies!
    nodes.each do |node|

      adjacencies[node]  = []
      node.edges.each do |edge|
        other = edge.not_node node

        # We use the edge length later on, so we might as well store it here
        # The `if` statement here is because these nodes are otherwise
        # completely connected, so we want to make sure that this graph is
        # restricted to the subset of nodes that we pass in.
        #
        # You are correct in thinking that I did not myself remember this
        # for many hours.
        adjacencies[node] << [other, edge] if nodes.include? other
      end
    end
  end

  def size
    nodes.size
  end

  def inspect
    "#<#{self.class.name}:#{object_id} @nodes=[#{nodes.size} nodes]>"
  end

  def &(other)
    nodes & other.nodes
  end
end

class DisjointGraph < Graph

  # There's an optimization in here, I'm sure, but I don't care to find it
  def connected_subgraphs
    uf    = UnionF.new nodes
    edges = nodes.map {|n| n.edges }.flatten
                 .filter {|e| (e.nodes - nodes).empty? }
  
    edges.each do |edge|
      # no-op if they're already unioned
      uf.union edge.nodes[0], edge.nodes[1]
    end
  
    uf.disjoint_sets.map {|djs| ConnectedGraph.new djs }
  end
end

class ConnectedGraph < Graph
  include Siting

  # Maybe this could be moved to `Graph`, but I'm not sure this fully
  # makes sense for a disjoint graph.
  def border_nodes
    nodes.filter {|n| not (n.edges.map {|e| e.nodes }.flatten - nodes).empty? }
  end

  def generators_for_clusters(power=10, &k)
    cluster(k[nodes.size]).map do |cluster|
      graph = ConnectedGraph.new cluster.points
      Generator.new graph, graph.longest_path.median, power
    end
  end

  def demand
    nodes.map {|n| n.load }.sum
  end

  # BFS
  def traverse_edges(source, &block)
    visited = Set.new

    # Probably should replace this with a deque
    queue = []
    queue   << source
    visited << source

    until queue.empty?
      from = queue.shift

      adjacencies[from].each do |to, edge|
        unless visited.include? to
          block.call edge, from, to
          queue   << to
          visited << to
        end
      end
    end

    visited
  end

  # Hell yeah baby, memoization for the motherfucking win
  def path(from: nil, to: nil)
    track "$elapsed" do
      @paths ||= {}

      if from == to
        []
      elsif @paths[from]
        @paths[from][to]
      else
        path = {from => []}

        traverse_edges from do |edge, sta, iin|
          path[iin] = path[sta] + [edge]
        end

        @paths[from] = path
        path[to]
      end
    end
  end

  def manhattan_distance(from: nil, to: nil)
    path(from: from, to: to).size
  end

  def longest_path
    node,  _ = farthest_node_from nodes[0]
    start, _ = farthest_node_from node

    Path.build path(from: start, to: node)
  end

  def longest_path_from(source)
    node, _ = farthest_node_from source

    Path.build path(from: source, to: node)
  end
  
  def total_edge_length
    adjacencies.values.flatten(1).uniq.map {|n, e| e.length }.sum
  end

  def farthest_node_from(source, &blk)
    blk ||= proc {|e| e.length }

    distance = Hash.new {|h, k| h[k] = -1 }
    distance[source] = 0

    traverse_edges source do |edge, from, to|
      distance[to] = distance[from] + blk[edge]
    end

    distance.max_by {|k, v| v }
  end

  # TODO integrate KMeansPP into the graph class. Maybe?
  def cluster(clusters=3)
    # Final part of this line is a little tailored to the node class, but
    # I guess that's okay? The proc is to provide pertinent serialization
    # across processes during parallelization. I suppose a graph and its
    # nodes have to be made with each other in mind.
    KMeansPP.clusters(nodes, [clusters, nodes.size].min) {|n| n.to_a }
  end
end


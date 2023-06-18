require 'set'
require_relative "resilience.rb"

class Graph
  include Resilience

  attr_accessor :nodes

  # Need to specify the nodes, and then restrict the edges to only those
  # that connect to these nodes
  def initialize(nodes)
    raise unless nodes[0] == nil ||
                 nodes[0].class == Node
    @nodes = nodes
    @adjacencies = nil

    adjacencies
  end

  def reset!
    @edges = nil
    @adjacencies = nil

    adjacencies
  end

  def edges
    @edges ||= nodes.map {|n| n.edges.filter {|e| e.nodes - nodes == [] } }.flatten.uniq
  end

  def adjacencies
    return @adjacencies if @adjacencies

    set = Set.new nodes
    @adjacencies = {}
    nodes.each do |node|

      @adjacencies[node] = []
      node.edges.each do |edge|
        other = edge.not_node node

        # We use the edge length later on, so we might as well store it here
        # The `if` statement here is because these nodes are otherwise
        # connected, so we want to make sure that this graph is restricted to
        # the subset of nodes that we pass in.
        #
        # You are correct in thinking that I did not myself remember this
        # for many hours.
        @adjacencies[node] << [other, edge] if set.include? other
      end
    end

    @adjacencies
  end

  def adjacency_matrix
    return @adj if @adj

    adj = nodes.size.times.map { [0] * nodes.size }

    nodes.each do |node|
      @adjacencies[node].each do |other, edge|
        adj[node.id][other.id] = 1
      end
    end

    @adj = Matrix[*adj]
  end

  # BFS
  # Gets all edges. Some nodes will be reached twice in a cyclic graph.
  # Args to the block: edge, from, to
  def traverse_edges(source, &block)
    visited = Set.new

    # Probably should replace this with a deque
    queue   = []

    # if `source` is an array, have multiple search roots
    if source.is_a? Array
      queue += source
    else
      queue << source
    end

    until queue.empty?
      from = queue.shift

      adjacencies[from].each do |to, edge|
        unless visited.include? edge
          block.call edge, from, to
          queue   << to
          visited << edge
        end
      end
    end

    visited
  end

  # BFS
  # This traverses all edges and nodes in an acyclic graph
  # This traverses all nodes but does NOT traverse all edges in a cyclic
  # graph
  # Args to the block: edge, from, to
  def traverse_nodes(source, &block)
    visited = Set.new

    # Probably should replace this with a deque
    queue   = []

    # if `source` is an array, have multiple search roots
    if source.is_a? Array
      queue   += source
      visited += source
    else
      queue   << source
      visited << source
    end

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

  def load
    nodes.map {|n| n.load }.sum
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


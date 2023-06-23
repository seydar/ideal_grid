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
    @spots = nodes.map.with_index.to_h
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
      adjacencies[node].each do |other, edge|
        adj[@spots[node]][@spots[other]] = 1
      end
    end

    @adj = Matrix[*adj]
  end

  def source_adjacency_matrix(sources)
    return @g_adj if @g_adj

    adj = nodes.size.times.map { [0] * nodes.size }

    sources.each do |node|
      adjacencies[node].each do |other, edge|
        adj[@spots[node]][@spots[other]] = 1
      end
    end

    @g_adj = Matrix[*adj]
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

  # Removes excess nodes (where load == 0) and produces new edges
  def simplify(keep: [])
    # Save loads and junctions and dead-ends (to preserve # of paths)
    set          = Set.new(nodes.filter {|n| n.load > 0 || n.edges.size != 2 } +
                           keep)
    loads_n_jxns = set.to_a # remove possible duplicates from `keep`

    # Take each node we want to keep in our Brave New World
    #   Follow their edges until we get to a saveable node
    #   Create an edge from our node to the next saveable node
    new_edges = loads_n_jxns.map do |node|
      node.edges.map do |edge|
        nxt, dist = follow(edge.not_node(node), :from => node, :within => set)
        [node, nxt, dist + edge.length]
      end
    end

    # New nodes for the new world
    new_nodes = loads_n_jxns.map(&:dup)
    new_nodes.each {|n| n.edges = [] }
    lookup = new_nodes.map {|n| [n.id, n] }.to_h
    
    # Now we need to convert the edges to the new edges
    #   flatten it all to be [[from, to], ...]
    new_edges = new_edges.flatten(1).filter {|_, n_2, _| n_2 }

    #   remove duplicates (in case of two dumb paths between two loads)
    new_edges = new_edges.uniq {|n_1, n_2, _| [n_1.id, n_2.id].sort }

    #   remove edges where p_1 == p_2 because a useless loop was removed
    new_edges = new_edges.filter {|p_1, p_2, _| p_1 != p_2 }

    #   look up the nodes to be their new clones
    #   create the edges
    new_edges = new_edges.map.with_index do |(from, to, dist), i|
      p_1  = lookup[from.id]
      p_2  = lookup[to.id]
      #dist = p_1.euclidean_distance p_2

      raise if p_1 == p_2

      Edge.new p_1, p_2, dist, :id => i
    end

    # Okay, now we have the edges that will exist in our new world
    new_edges.each {|e| e.attach! }

    new_nodes
  end

  # Assumes no junctions, so each node will only have 2 edges
  def follow(node, from: nil, within: [])
    return [node, 0] if node.edges.size > 2

    nxt  = (node.edges.map(&:nodes).flatten - [from, node])[0]
    edge = node.edges.find {|e| e.nodes.include? nxt }

    if within.include? nxt
      [nxt, edge.length]
    elsif nxt.nil?
      # TODO throw a print in here to make sure it's right
      [nil, 0]
    else
      n, d = follow nxt, :from => node, :within => within
      [n, d + edge.length]
    end
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


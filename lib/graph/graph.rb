require 'set'

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
        adjacencies[node] << [other, edge] if nodes.include? other
      end
    end
  end

  # BFS
  def traverse_edges(source, &block)
    visited  = Set.new

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

  def longest_path
    node,  dist = longest_path_from nodes[0]
    start, dist = longest_path_from node

    Path.build start.path_to(node)
  end
  
  def total_edge_length
    adjacencies.values.flatten(1).uniq.map {|n, e| e.length }.sum
  end

  def longest_path_from(source)
    distance = Hash.new {|h, k| h[k] = -1 }
    distance[source] = 0

    traverse_edges source do |edge, from, to|
      distance[to] = distance[from] + edge.length
    end

    distance.max_by {|k, v| v }
  end
end


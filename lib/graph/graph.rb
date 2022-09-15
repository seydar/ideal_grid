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
end


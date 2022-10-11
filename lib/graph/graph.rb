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

  def inspect
    "#<#{self.class.name}:#{object_id} @nodes=[#{nodes.size} nodes]>"
  end
end

class DisjointGraph < Graph

  # There's an optimization in here, I'm sure, but I don't care to find it
  def connected_subgraphs
    uf    = UnionF.new nodes
    edges = nodes.map {|n| n.edges }.flatten
                 .reject {|e| not e.nodes.all? {|n| nodes.include? n } }
  
    edges.each do |edge|
      unless uf.connected? edge.nodes[0], edge.nodes[1]
        uf.union edge.nodes[0], edge.nodes[1]
      end
    end
  
    uf.disjoint_sets.map {|djs| ConnectedGraph.new djs }
  end
end

class ConnectedGraph < Graph

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

  # TODO integrate KMeansPP into the graph class. Maybe?
  def cluster(clusters=3)
    # Final part of this line is a little tailored to the node class, but
    # I guess that's okay? The proc is to provide pertinent serialization
    # across processes during parallelization. A graph and its nodes have
    # to be made with each other in mind.
    KMeansPP.clusters(nodes, [clusters, nodes.size].min) {|n| n.to_a }
  end
end


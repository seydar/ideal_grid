require 'set'
require_relative "../siting.rb"

class Graph
  attr_accessor :nodes

  # Need to specify the nodes, and then restrict the edges to only those
  # that connect to these nodes
  def initialize(nodes)
    @nodes = nodes
    @adjacencies = nil

    fill_adjacencies!
  end

  def adjacencies
    return @adjacencies if @adjacencies
    fill_adjacencies!
    @adjacencies
  end

  def fill_adjacencies!
    @adjacencies = {}
    nodes.each do |node|

      @adjacencies[node]  = []
      node.edges.each do |edge|
        other = edge.not_node node

        # We use the edge length later on, so we might as well store it here
        # The `if` statement here is because these nodes are otherwise
        # completely connected, so we want to make sure that this graph is
        # restricted to the subset of nodes that we pass in.
        #
        # You are correct in thinking that I did not myself remember this
        # for many hours.
        @adjacencies[node] << [other, edge] if nodes.include? other
      end
    end
  end

  # BFS
  # Gets all edges. Some nodes will be reached twice in a cyclic graph.
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

  # BFS
  def traverse_edges_in_phases(source, block1, block2)
    visited = Set.new

    # Probably should replace this with a deque
    queue   = []
    next_queue = []

    # if `source` is an array, have multiple search roots
    if source.is_a? Array
      queue  += source
    else
      queue  << source
    end

    continue = true # I hate this double declaration but yolo
    while continue
      continue = false

      until queue.empty?
        from = queue.shift

        adjacencies[from].each do |to, edge|
          unless visited.include? edge
            success = block1.call edge, from, to
            continue |= success

            # (This is all custom-built for determining reach)
            # If the generator doesn't have enough juice, then we don't want
            # to continue down that branch. We'll keep checking it though
            #
            # `success` is also used to determine whether we do another loop:
            # if there's at least one success, then we've got >= 1 new branch
            # to explore
            if success
              # The conditional here is for future work where the graph
              # is cyclic
              next_queue << to unless next_queue.include? to
              visited << edge
            else
              # a single node can have multiple edges which will
              # all have the same `from`! This prevents `next_queue` from
              # blowing up
              next_queue << from unless next_queue.include? from
            end
          end
        end
      end

      # Do something else now that one unit of time has passed and all sources
      # have been explored simultaneously
      block2.call visited

      queue, next_queue = next_queue, []
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

  def initialize(nodes)
    raise "nodes cannot be empty" if nodes.empty?
    super(nodes)
  end

  def manhattan_distance_from_group(node)
    return 0 if nodes.include? node

    # Can't use the internal memoized version because that is only good for
    # paths within the graph. Here, we are -- by definition -- talking about
    # nodes that are outside the graph
    border_nodes.map {|n| n.manhattan_distance  node }.min
  end

  # Maybe this could be moved to `Graph`, but I'm not sure this fully
  # makes sense for a disjoint graph.
  def border_nodes
    nodes.filter {|n| not (n.edges.map {|e| e.nodes }.flatten - nodes).empty? }
  end

  def nodes_just_beyond
    nodes.map {|n| n.edges.map {|e| e.nodes } }.flatten - nodes
  end

  def touching(graph)
    graph.nodes & nodes_just_beyond != []
  end

  # `k` is how many clusters we want
  # `power` should also prolly be a function as well
  def generators_for_clusters(grid, power=10, &k)
    cluster(k[nodes.size]).map do |cluster|
      cg = ConnectedGraph.new cluster.points

      # If there's only one cluster, then there will be no border nodes
      # so on-premises siting won't work
      if cluster.points.size == 1 || k[nodes.size] <= 1
        Generator.new grid.graph, cluster.points[0], power
      else
        Generator.new grid.graph, cg.site_on_premises, power
      end
    end
  end

  def demand
    nodes.map {|n| n.load }.sum
  end

  # Hell yeah baby, memoization for the motherfucking win
  # This used to be like 8s on 500 nodes and 10 clusters, and now
  # it's 0.2s
  #
  # Note: this only returns the minimum # of edges to a node. Dijkstra's
  # algorithm is what is required in order to account for edge weight
  def path(from: nil, to: nil)
    @paths ||= {}

    return [] if from == to
    return @paths[from][to] if @paths[from]

    @paths[from] = {from => []}
    traverse_edges from do |edge, sta, iin|
      @paths[from][iin] = @paths[from][sta] + [edge]
    end

    @paths[from][to]
  end

  # Spoil the cache
  def invalidate_cache!
    @paths = nil
    @adjacencies = nil
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


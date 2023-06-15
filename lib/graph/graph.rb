require 'set'
require_relative "../siting.rb"

class Graph
  attr_accessor :nodes

  # Need to specify the nodes, and then restrict the edges to only those
  # that connect to these nodes
  def initialize(nodes)
    raise unless nodes[0] == nil ||
                 nodes[0].class == Node
    @nodes = nodes
    @adjacencies = nil

    fill_adjacencies!
  end

  def reset!
    @edges = nil
    @adjacencies = nil

    fill_adjacencies!
  end

  def edges
    @edges ||= nodes.map {|n| n.edges.filter {|e| e.nodes - nodes == [] } }.flatten.uniq
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

  # \Sigma 1 / ((d(u) * d(v)) ^ 1/2)
  # u, v for all edges(u, v) in G
  def randic_index
    edges.sum do |edge|
      sqrt = Math.sqrt(edge.nodes[0].edges.size * edge.nodes[1].edges.size)
      1.0 / sqrt
    end
  end

  # Used only from the major overarching graph
  def manhattan_distance_from_group(node, group)
    return 0 if nodes.include? node

    group.border_nodes.map {|n| manhattan_distance :from => node, :to => n }.min
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
    puts "\tCreating #{k[nodes.size]} clusters"
    cluster(k[nodes.size]).clusters.map do |cluster|
      pts = cluster.points.map {|p| p.label }
      cg = ConnectedGraph.new pts

      # If there's only one cluster, then there will be no border nodes
      # so on-premises siting won't work
      if cluster.points.size == 1 || k[nodes.size] <= 1
        Generator.new grid.graph, pts[0], power
      else
        # Siting at the median because we're now concerned with high flow
        # #site_on_premises is better for disjoint graphs, and #site_median
        # is better for clusters in a single connected graph
        Generator.new grid.graph, cg.site_median, power
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
    path(from: from, to: to).sum {|e| e.length }.to_f
  end

  def longest_path
    node,  _ = farthest_node_from nodes[0]
    start, _ = farthest_node_from node

    Path.build path(from: start, to: node)
  end

  def median_node
    lp = longest_path

    if lp.empty?
      nodes[0]
    else
      lp.median
    end
  end

  def longest_path_from(source)
    node, _ = farthest_node_from source

    Path.build path(from: source, to: node)
  end
  
  def total_edge_length
    adjacencies.values.flatten(1).uniq.map {|n, e| e.length }.sum
  end

  # Distances are calculated per edge based on `blk`. By default, blk
  # is `proc {|e| e.length }`, which computes distance based on the length
  # of the edge. If you were to do `proc { 1 }`, then it would be the number of
  # edges that you have to pass through.
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

    data = nodes.map {|n| n.to_a }
    KMeansClusterer.run [clusters, nodes.size].min,
                        data,
                        :labels => nodes,
                        :runs => 1
  end

  # I don't care enough to come up with this myself. I prolly wouldn't do a
  # good job anyways.
  #
  # Now it's parallelized, but it can sometimes get overwhelmed with datasets
  # that are too large. How can I split a graph up into smaller partitioned chunks?
  # FIXME ^^^
  #
  # https://www.geeksforgeeks.org/shortest-cycle-in-an-undirected-unweighted-graph/
  def separate_cycles
    id_map = nodes.map {|n| [n.id, n] }.to_h
    #answers = nodes.parallel_map(:cores => 4) do |node|
    answers = nodes.map do |node|
      ans = nil
      path = {}
      par  = {}
      visited = Set.new

      path[node] = [node]
      visited << node
      q = [node]

      until q.empty?
        x = q.shift

        @adjacencies[x].each do |child, edge|

          # If unvisited
          if not visited.include?(child)
            path[child] = path[x] + [child]
            par[child]  = x
            visited << child
            q << child
          elsif par[x] != child && par[child] != x
            if ans
              ans = [ans,
                     path[x] + path[child]]
                    .min_by {|v| v.size }
            else
              ans = path[x] + path[child]
            end
          end
        end
      end

      ans
    end

    # Put everything into the same terms
    # (preparing for bringing back multithreading)
    res = answers.compact.map do |ans|
      ans.map {|n| id_map[n.id] }.uniq # make everything use the original same set of nodes
    end

    # Filter to only the small ones
    res = res.filter {|cyc| cyc.size <= 5 }

    # Now that everything is normalized, we can actually identify the separate
    # cycles, which means looking for cycles whose edges are fully unique among
    # the rest of the set
    uf = UnionF.mark res do |c1, c2|
      es_i = c1.map(&:edges).flatten.uniq
      es_j = c2.map(&:edges).flatten.uniq
      es_i & es_j != []
    end

    uf.disjoint_sets.map {|c| c.min_by(&:size) }
  end

  def shortest_cycle
    separate_cycles.min_by {|c| c.size }
  end
end


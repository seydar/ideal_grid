require_relative 'graph.rb'
require_relative 'siting.rb'

class ConnectedGraph < Graph
  include Siting

  def initialize(nodes)
    raise "nodes cannot be empty" if nodes.empty?
    super(nodes)
  end

  # grow a CG by a certain number of steps
  def expand(steps: 5)
    handful = nodes

    steps.times do
      border_nodes = handful.map do |node|
        node.edges.map {|e| e.not_node node }
      end.flatten
      new_nodes = border_nodes - handful
      handful += new_nodes
    end

    ConnectedGraph.new handful
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
end


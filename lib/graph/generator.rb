class Generator
  attr_accessor :cluster
  attr_accessor :node
  attr_accessor :graph
  
  def initialize(cluster)
    @cluster = cluster
    @node    = cluster.centroid.original
    @graph   = Graph.new(cluster.points)
  end
  
  # requires an MST
  # demand == node.edges.map {|e| e.demand }.sum
  def demand
    graph.total_edge_length
  end
  
  def flow
    node.edges.map do |edge|
      edge.flow :from => node, :restrict => cluster.points
    end.sum + node.load
  end

  # >10x as fast as the recursive version
  def flow_loop
    queue = []

    graph.traverse_edges node do |edge, from, to|
      queue << [edge, from, to]
    end

    flows = Hash.new {|h, k| h[k] = k.load }
    queue.reverse.each do |edge, from, to|
      flows[from] += flows[to]
    end

    flows[node]
  end

end


class Generator
  attr_accessor :cluster
  attr_accessor :node
  attr_accessor :graph
  
  def initialize(cluster)
    @cluster = cluster
    @node    = cluster.centroid.original
  end
  
  # requires an MST
  # demand == node.edges.map {|e| e.demand }.sum
  def demand
    @graph = Graph.new(cluster.points)
    graph.total_edge_length
  end
  
  def flow
    node.edges.map do |edge|
      edge.flow :from => node, :restrict => cluster.points
    end.sum + node.load
  end
end


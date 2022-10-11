class Generator
  attr_accessor :cluster
  attr_accessor :node
  attr_accessor :graph
  attr_accessor :power
  
  def initialize(cluster, power=0)
    @cluster = cluster
    @node    = cluster.centroid.original
    @graph   = ConnectedGraph.new cluster.points
    @power   = power
  end
  
  # requires an MST
  # demand == node.edges.map {|e| e.demand }.sum
  def total_line_length
    graph.total_edge_length
  end

  # >10x as fast as the recursive version
  def demand
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

  # How far will the generator's power go before it's lost? 
  def reach
    return @reach if @reach

    reachable = []
    remainder = power

    graph.traverse_edges node do |edge, from, to|
      if remainder - from.load > 0
        reachable << from
        remainder -= from.load
      end
    end

    @reach = {:nodes => reachable, :remainder => remainder}
  end

  def info
    str = ""
    str << "\tCluster #{node.inspect}\n"
    str << "\t\tCalculated demand: #{demand}\n"
    str << "\t\tTotal line length: #{total_line_length}\n"
    str << "\t\tLongest path: #{graph.longest_path.length}\n"
    str << "\t\t\t      #{graph.longest_path.edges.size} edges\n"
    str << "\t\tTotal nodes: #{graph.nodes.size}"
    str
  end
end


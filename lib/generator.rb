class Generator
  attr_reader :node
  attr_reader :graph
  attr_reader :demand

  attr_accessor :power
  attr_accessor :reach
  attr_accessor :remainder
  
  def initialize(graph, node, power=0)
    @graph = graph
    @node  = node
    @power = power

    calculate_reach!
  end

  # This will make more sense once there are different types of generators
  # (solar, nuclear, wind, etc)
  def enlargeable?
    true
  end

  def total_line_length
    ConnectedGraph.new(reach[:nodes]).total_edge_length
  end

  # How far will the generator's power go before it's lost? 
  def calculate_reach!
    reachable = [node]
    remainder = power - node.load

    if remainder < 0
      raise "Generator can't power itself (node.load > gen.power)"
    end

    graph.traverse_edges node do |edge, from, to|
      if remainder - to.load >= 0
        reachable << to
        remainder -= to.load
      end
    end

    @reach  = ConnectedGraph.new reachable
    @demand = power - remainder
  end

  def info
    str = ""
    str << "\tCluster #{node.inspect}\n"
    str << "\t\tCalculated demand: #{demand}\n"
    str << "\t\tTotal line length: #{total_line_length}\n"
    str << "\t\tLongest path: #{reach.longest_path.length}\n"
    str << "\t\t\t      #{reach.longest_path.edges.size} edges\n"
    str << "\t\tTotal nodes: #{reach.size}"
    str
  end
end


class Generator
  attr_reader :node
  attr_reader :graph

  attr_accessor :power
  
  def initialize(graph, node, power=0)
    @graph = graph
    @node  = node
    @power = power
  end

  # This will make more sense once there are different types of generators
  # (solar, nuclear, wind, etc)
  def enlargeable?
    true
  end

  def total_line_length
    ConnectedGraph.new(reach[:nodes]).total_edge_length
  end

  def info
    str = ""
    str << "\tCluster #{node.inspect}\n"
    str << "\t\tPower: #{power}\n"
    str << "\t\tTotal nodes: #{reach.size}"
    str
  end
end


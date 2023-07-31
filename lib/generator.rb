class Generator
  attr_accessor :graph
  attr_accessor :node
  attr_accessor :power
  
  def initialize(graph, node, power=0)
    @graph = graph
    @node  = node
    @power = power
  end

  def within?(bounds)
    node.within? bounds
  end

  # This will make more sense once there are different types of generators
  # (solar, nuclear, wind, etc)
  def enlargeable?
    true
  end

  def info
    str = ""
    str << "\tCluster #{node.inspect}\n"
    str << "\t\tPower: #{power}\n"
    str
  end

  def manhattan_distance(other)
    graph.manhattan_distance :from => node, :to => other
  end

  def path_to(other)
    graph.path(:from => node, :to => other)
  end
end


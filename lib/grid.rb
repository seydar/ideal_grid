class Grid
  # Truly just a bit of encapsulation to keep track of some nodes (and edges)
  # and their associated generators

  attr_accessor :nodes
  attr_accessor :generators
  attr_accessor :graph

  def initialize(nodes, generators)
    @nodes      = nodes
    @generators = generators
    @graph      = ConnectedGraph.new nodes
  end

  def unreached
    reached = generators.map {|g| g.reach.nodes }.flatten
    DisjointGraph.new(nodes - reached)
  end

  def inspect
    "#<Grid: @nodes=[#{nodes.size} nodes] @generators=[#{generators.size} generators]>"
  end
end

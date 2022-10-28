class Grid
  attr_accessor :nodes
  attr_accessor :generators
  attr_accessor :graph
  attr_accessor :reach

  def initialize(nodes, generators)
    @nodes      = nodes
    @generators = generators
    @graph      = ConnectedGraph.new nodes
  end

  def analyze
    Analyzer.new reach, generators
  end

  def unreached
    DisjointGraph.new(nodes - reach.nodes)
  end

  def power
    generators.map {|g| g.power }.sum
  end

  def inspect
    "#<Grid: @nodes=[#{nodes.size} nodes] @generators=[#{generators.size} generators]>"
  end

  def calculate_reach!
    reachable = generators.map {|g| g.node }
    loads     = generators.map {|g| g.node.load }.sum
    remainder = power - loads

    if remainder < 0
      raise "Generators can't power themselves (node.load > gen.power across all gens)"
    end

    # Start with the generator nodes as the sources
    graph.traverse_nodes reachable do |edge, from, to|
      if remainder - to.load >= 0
        reachable << to
        remainder -= to.load
      end
    end

    @reach = ConnectedGraph.new reachable
  end
end

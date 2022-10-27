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

  def unreached
    DisjointGraph.new(nodes - reach.nodes)
  end

  def power
    generators.map {|g| g.power }.sum
  end

  def inspect
    "#<Grid: @nodes=[#{nodes.size} nodes] @generators=[#{generators.size} generators]>"
  end

  # Assumes connected graph and generators are in the graph (duh)
  # This does NOT traverse all edges. This merely traverses all nodes.
  def traverse_nodes(&block)
    # This is the only difference between this implementation and the
    # implementation in `Graph`: we are starting with multiple sources
    # instead of just one.
    sources = generators.map {|g| g.node }
    visited = Set.new

    # Probably should replace this with a deque
    queue = []
    queue   += sources
    visited += sources

    until queue.empty?
      from = queue.shift

      graph.adjacencies[from].each do |to, edge|
        unless visited.include? to
          block.call edge, from, to
          queue   << to
          visited << to
        end
      end
    end

    visited
  end

  def calculate_reach!
    reachable = generators.map {|g| g.node }
    loads     = generators.map {|g| g.node.load }.sum
    remainder = power - loads

    if remainder < 0
      raise "Generators can't power themselves (node.load > gen.power across all gens)"
    end

    traverse_nodes do |edge, from, to|
      if remainder - to.load >= 0
        reachable << to
        remainder -= to.load
      end
    end

    @reach = ConnectedGraph.new reachable
  end
end

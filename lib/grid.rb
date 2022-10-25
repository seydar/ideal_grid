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

  def generator_for_node(node)
    generators.min_by do |gen|
      graph.manhattan_distance(from: gen.node, to: node)
    end
  end

  def calculate_reaches
    reaches = Hash.new {|h, k| h[k] = [] }
    nodes.each do |node|
      g = generator_for_node node
      reaches[g] << node
    end

    reaches.each do |gen, reach|
      gen.reach = ConnectedGraph.new reach
    end
  end
end

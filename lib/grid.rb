class Grid
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

  # TODO what if two nodes are equidistant from a generator with only 1 power left?
  # Who gets it then?
  def generator_for_node(node)
    generators.filter {|g| g.remainder > 0 }.min_by do |gen|
      graph.manhattan_distance(from: gen.node, to: node)
    end
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

  def calculate_reach
    reachable = generators.map {|g| g.node }
    power     = generators.map {|g| g.power }.sum
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

    {:reach => ConnectedGraph.new(reachable),
     :demand => power - remainder,
     :remainder => remainder}
  end

  # FIXME
  # This picks out points at random, and the power counter is decremented on a
  # first-come-first-serve basis, but that isn't based on proximity to the
  # generator, but instead the random assortment of points.
  #
  # So don't decrement until you can sort
  # Which means we're going to have to iterate:
  #   1. Associate nodes with generators
  #   2. See how many nodes a generator can support
  #   3. Take the remaining nodes and find new homes for them
  def old_calculate_reaches
    generators.each do |g|
      g.remainder = g.power - 1
      g.reach = ConnectedGraph.new [g.node]
    end

    i = 0
    reaches = Hash.new {|h, k| h[k] = [] }
    nodes.each do |node|
      g = generator_for_node node
      g.remainder -= 1
      reaches[g] << node

      puts "#{node.inspect}\tattached to [#{g.power}]#{g.node.inspect}"
      plot_graph graph, :color => "gray"

      generators.each.with_index do |gen, i|
        color = COLORS[i % COLORS.size]
        plot_points reaches[gen], :color => color
        plot_point gen.node, :color => color, :point_type => 7
      end
      save_plot "images/#{i}.png"
      i += 1
    end

    # First, get those that are closest to their generators.
    # These are the freebies.
    unreached = reaches.delete nil
    reaches.each do |gen, reach|
      gen.reach      = ConnectedGraph.new reach
    end

    # Next, look at the remaining unreached nodes -- who's the closest that still has
    # power?
    # Really, we could just use this method from the start. Perhaps we should.
  end
end

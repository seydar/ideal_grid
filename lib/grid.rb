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

  def calculate_reaches
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

      g.reach = ConnectedGraph.new(reaches[g])
      plot_graph graph, :color => "gray"

      generators.each.with_index do |gen, i|
        color = COLORS[i % (COLORS.size - 1)]
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

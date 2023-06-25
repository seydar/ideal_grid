require_relative "flow.rb"
require_relative "power.rb"

class Grid
  include Flow
  include Power

  # According to the EIA:
  #   DC consumed 37 trillion BTU in 2020
  #     ~ 10843629596.372223 kWh
  #     ~ avg 1237857.25986 kW
  #     ~ avg 1238 MW
  #
  #   NH:
  #     296 trillion BTU in 2020
  #     ~ 86749036770.97778 kWh
  #     ~ avg 9902858.07888 kW
  #     ~ avg 9903 kW
  #
  #   LNG turbine: 250 kW
  #   Nuclear: 1000 kW
  #
  #   For modeling NH, call it 990 nodes, LNG 25, nuclear 100

  attr_accessor :nodes
  attr_accessor :loads
  attr_accessor :generators
  attr_accessor :graph
  attr_accessor :freq
  attr_accessor :flows
  attr_accessor :losses

  # This method used to make more sense, I promise, but now it's pretty useless
  def self.within(box, fuel: {})
    lines   = Line.within box

    from :lines => lines, :fuel => fuel
  end

  # FIXME
  # The whole shitshow here is a disjoint graph, with transmission lines being
  # disjoint, and thus sources and loads being disjoint. If we are able to take
  # all of the transmission lines and identify the largest connected subgraph,
  # we need to then restrict our sources and loads to only be those that are on
  # that connected subgraph.
  #
  # Currently, I do no such restriction.
  #
  # This, as you might imagine, is bad. Errors abound. Code refuses to run.
  # Nobody wants to work these days!
  #
  # Any changes I make here can be removed once I get Grid to work with disjoint
  # graphs.
  def self.from(lines: [], fuel: {})
    # So.
    #
    # Because edges already exist between all the loads and sources and the
    # infrastructure, `t_nodes` will already contain all of the points as
    # `Point` instances for both loads and sources.
    #
    # However, when we turn them into instances of `Node`, we want to make sure
    # the loads are correct for the loads, so we need to specifically generate
    # those nodes and merge them into our list.
    # Get the nodes
    points = lines.map {|l| [l.left, l.right] }.flatten.uniq
    nodes  = points.map do |pt|
      [pt, Node.new(pt.x, pt.y, :id => pt.id, :draws => 0, :point => pt)]
    end.to_h

    # Build edges from the lines
    edges = lines.map do |line|
      Edge.new nodes[line.left],
               nodes[line.right],
               line.length,
               :id => line.id,
               :voltage => line.voltage
    end
    edges.each {|e| e.attach! }

    # The nodes are likely disjoint, and we can only operate on a connected
    # graph, so we're going to use our tooling to find the largest connected
    # graph and base the grid on that and that alone.
    #
    # NB: since 4/21/23, the graph I'm using is connected, so this is
    # *technically* wasteful, but I'm not sure I want to get rid of it just yet,
    # since it'll force me to always have connected graphs for regions
    # TODO evaluate then make a decision
    dg = DisjointGraph.new nodes.values
    cg = dg.connected_subgraphs.max_by {|cg| cg.nodes.size }
    cg_points = cg.nodes.map {|n| n.point }

    # Now that we have our connected graph, let's figure out which loads and
    # sources are found along it.
    #
    # Eager loading because there's no need to be wasteful in our DB calls
    loads   = Load.eager(:point).filter(:point => cg_points).all
    sources = Source.by_fuel_mix(fuel) { (oper_cap > 0) & {:point => cg_points} }

    loads.each do |l|
      nodes[l.point].load = l.max_peak_load || 1
    end

    gens = sources.map do |s|
      nodes[s.point].load = 0
      Generator.new cg, nodes[s.point], s.oper_cap
    end

    # Our grid!
    new cg, gens
  end

  def initialize(nodes, generators)
    @generators = generators
    @freq       = 0
    @losses     = {}

    if ConnectedGraph === nodes
      @nodes = nodes.nodes
      @graph = nodes
    else
      @nodes = nodes
      @graph = ConnectedGraph.new nodes
    end

    @generators.each {|g| g.graph = @graph }
    @loads = @nodes.filter {|n| n.load > 0 }
    @map   = @nodes.map {|n| [n.id, n] }.to_h # for use after parallelization
  end

  def simplify
    new_nodes = graph.simplify :keep => generators.map(&:node)

    # Clone the generators and remap them to their new nodes
    gens = generators.map do |gen|
      g = gen.dup
      g.node = new_nodes.find {|n| n.id == g.node.id }
      g
    end

    # Our new grid!
    self.class.new new_nodes, gens
  end

  def resiliency(type=:drakos, *vars)
    if type == :drakos
      graph.j *vars
    elsif type == :estrada
      graph.estrada *vars
    end
  end

  def power
    generators.map {|g| g.power }.sum
  end

  def inspect
    loads = nodes.filter {|n| n.load > 0 }
    "#<Grid: @nodes=[#{nodes.size} nodes, #{loads.size} loads] @generators=[#{generators.size} generators]>"
  end

  # Two hardest problems in computer science
  def reset!
    graph.invalidate_cache!
    calculate_flows!
  end

  # How far away are two connected graphs?
  def group_distance(cg1, cg2)
    graph.manhattan_distance :from => cg1.median_node, :to => cg2.median_node
  end

  def transmission_loss
    node_load = @loads.sum(&:load)
    tx_loss = losses.values.sum
    total_load = node_load + tx_loss

    [tx_loss, (100 * tx_loss / total_load.to_f).round(2)]
  end

  def info
    str = ""
    node_load = @loads.sum(&:load)
    tx_loss = losses.values.sum
    total_load = node_load + tx_loss
    str << "\tTotal load: #{total_load.round 2}\n"
    str << "\t\tNodes: #{node_load}\n"
    str << "\t\tTx losses: #{tx_loss.round(2)} "
    str <<      "(#{(100 * tx_loss / total_load.to_f).round 2}%)\n"
    str << "\tFrequency: #{Flow::BASE_FREQ + freq.round(2)} Hz (#{freq.round 2} Hz)\n"
    str << "\tPower: #{power} (#{generators.size} gens)\n"
    str << "\t\t#{generators.map {|g| g.power }}\n"
  end
end

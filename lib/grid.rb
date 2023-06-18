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
    edges.each {|e| e.mark_nodes! }

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

    @loads = @nodes.filter {|n| n.load > 0 }
  end

  def power
    generators.map {|g| g.power }.sum
  end

  def inspect
    loads = nodes.filter {|n| n.load > 0 }
    "#<Grid: @nodes=[#{nodes.size} nodes, #{loads.size} loads] @generators=[#{generators.size} generators]>"
  end

  def reset!
    graph.invalidate_cache!
    calculate_flows!
  end

  # Find the two closest nodes between the two CGs and draw a straight line
  # between them
  def connect_graphs(cg1, cg2)
    # Get the list of possible edges
    # Filter to only include those that don't currently exist
    # Sort with the shortest distance first
    rankings = cg1.nodes.product(cg2.nodes).map do |a, b|
      [a, b, a.euclidean_distance(b)]
    #end.filter {|a, b, d| not a.edge?(b) }.sort_by {|_, _, v| v }
    end.sort_by {|_, _, v| v }

    # DON'T mark the nodes -- simply provide the edge that accomplishes the mission.
    [Edge.new(rankings[0][0], rankings[0][1], rankings[0][2], :id => PRNG.rand),
     rankings[0][0],
     rankings[0][1]]
  end

  # grow a CG by a certain number of steps
  def expand(cg, steps: 5)
    handful = cg.nodes

    steps.times do
      border_nodes = handful.map do |node|
        node.edges.map {|e| e.not_node node }
      end.flatten
      new_nodes = border_nodes - handful
      handful += new_nodes
    end

    ConnectedGraph.new handful
  end

  def nodes_near(edge: nil, distance: 0)
    p1, p2 = *edge.nodes
    min_x, max_x = [p1.x, p2.x].min, [p1.x, p2.x].max
    min_y, max_y = [p1.y, p2.y].min, [p1.y, p2.y].max

    nodes.filter do |n|
      # This isn't glatt, but it's kosher enough
      next if n.x < min_x - distance 
      next if n.x > max_x + distance 
      next if n.y < min_y - distance 
      next if n.y > max_y + distance 

      d = edge.ray_distance_to_point n
      d <= distance
    end
  end

  # How far away are two connected graphs?
  def group_distance(cg1, cg2)
    graph.manhattan_distance :from => cg1.median_node, :to => cg2.median_node
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

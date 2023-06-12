class Grid
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

  # Constraints, in one place
  MAX_BUILD_POWER = 300 # units of power
  MAX_GROW_POWER  = 200
  THRESHOLD_FOR_BUILD = 20
  BASE_FREQ       = 60 # Hz

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

  def nearest_generator(node)
    generators.min_by {|g| graph.manhattan_distance :from => node, :to => g.node }
  end

  def build_generators_for_underfrequency(nodes_per_cluster)
    @flows
  end

  def build_generators_for_unreached(nodes_per_cluster)
    connected_graphs = [graph]

    biguns = connected_graphs.filter {|cg| cg.size > THRESHOLD_FOR_BUILD }

    old_size = generators.size

    biguns.each do |graph|
      pwr = [nodes_per_cluster, MAX_BUILD_POWER].min
      @generators += graph.generators_for_clusters(self, pwr) do |num|
        (num.to_f / nodes_per_cluster).ceil
      end
    end

    # It doesn't make sense to have a generator *also* have a load, especially
    # because that distance would be 0, which would really screw with the math
    # in `#calculate_flows!`
    @generators.each do |g|
      g.node.load = 0
      @loads.delete g.node
    end

    calculate_flows!

    generators.size - old_size
  end

  def grow_generators_for_unreached
    connected_graphs = [graph]

    liluns = connected_graphs.filter {|cg| cg.size <= THRESHOLD_FOR_BUILD }

    grown = 0
    liluns.each do |lilun|
      nearest_gen = generators.min_by {|g| graph.manhattan_distance_from_group g.node, lilun }
      old_power = nearest_gen.power

      # This is to a) set an upper limit on how power a generator can be,
      #        and b) to limit how much it can grow in a single iteration.
      # b) is pretty arbitrary. Can't remember why I wrote it in the first place.
      nearest_gen.power = [[nearest_gen.power + lilun.nodes.size, MAX_GROW_POWER].min,
                           nearest_gen.power + 5].min
      grown += 1 if old_power != nearest_gen.power
      calculate_flows!
    end

    calculate_flows!

    grown
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

  def reduce_congestion
    grouped_flows   = flows.group_by {|e, f| f }
    group_keys      = grouped_flows.keys.sort

    # Okay. Find the sources. The sources have to be *individual edges*, or
    # else we defeat the purpose of reducing the flow down those edges.
    # This isn't entirely true, but it's close enough for now.
    #
    # Options for sources:
    #   1. Build new edge that connects to a node on a high-flow edge
    #   2. Increase the load on a low-flow edge that already connects to a
    #      high-flow edge
    #
    #   (#2 feels like a general case of #1)
    #
    # Options for destinations:
    #   1. Connect the source to a low-flow CG.
    #      dafuq does this mean. Still an unsolved problem.
    #
    #      What does CG mean? Yes the CG is connected, but a graph of which
    #      nodes?
    #
    #      I think you can't just connect a high-flow edge to a random low-flow
    #      edge. There's a current (hah) of flow that is feeding a set of nodes,
    #      and if a generator now has to feed another region of nodes, then the
    #      original heavy current is unlikely to change (if the new region of
    #      nodes is too far away).
    #
    #      I need to basically create a circular connection so that heavy current
    #      gets a closer connection to the source.
    #
    # Nitpick: you don't connect an edge to an edge, you connect a node to a node
    # Yes, you connect edges, but in the interest of being deliberate with what
    # we do, we want to pick *nodes*.
    

    # Source; finding the medium-flow CG
    percentile = proc do |n|
      proc do |rng|
        (rng.begin * group_keys.size / n)..(rng.end * group_keys.size / n)
      end
    end

    range = percentile[10][6..8]
    selected_flows  = group_keys[range].map {|k| grouped_flows[k] }.flatten 1

    s_es = selected_flows.map {|e, f| e }

    nodes = s_es.map {|e| e.nodes }.flatten.uniq
    disjoint = DisjointGraph.new nodes

    selected_cgs = disjoint.connected_subgraphs.map do |cg|
      [cg, cg.edges.sum {|e| flows[e] }]
    end

    bounds = selected_cgs.map do |cg, sum|
      gen = nearest_generator cg.median_node
      dist = graph.path(:from => cg.median_node, :to => gen.node).size
      [cg, dist]
    end

    # For each CG, find another CG from another generator (outwardly expanding)
    # that can beat the current distance to a generator
    new_edges = bounds.map do |src, dist|
      new_edges = generators.map do |gen|
        # fuck it, dist - 1 is made up
        # How do we *actually* know whether we've sufficiently expanded a group
        # in our attempts to connect to it?
        tgt = expand ConnectedGraph.new([gen.node]), :steps => (dist - 3)

        # Find the ideal edge to connect these graphs
        e, _, _ = connect_graphs src, tgt
        next unless e.possible?

        # Somewhere in here, I need to add all of the nodes that are within a
        # certain distance of the line.
        ns = nodes_near :edge => e, :distance => 0.75
        #p "#{ns.size} nodes found near this edge"

        # Then, add all of those nodes and the nodes of the two base CGs into
        #   a DisjointGraph.
        dj = DisjointGraph.new(ns + src.nodes + tgt.nodes)

        # Then, get the two largest connected subgraphs.
        #subgraphs = dj.connected_subgraphs.sort_by {|cg| -cg.size }[0..1]

        # Then, get the two subgraphs that contact our targets
        subgraphs = dj.connected_subgraphs.filter do |cg|
          cg.nodes & src.nodes != [] or
            cg.nodes & tgt.nodes != []
        end

        next if subgraphs.size == 1
        # Then, connect that subgraphs
        e2, _, dst_n = connect_graphs *subgraphs

        #if e2.length < 0.5
        #  plot_grid self
        #  plot_points src.nodes, :color => "red"
        #  plot_points tgt.nodes, :color => "blue"
        #  plot_points ns, :color => "yellow"
        #  plot_edge e, :color => "orange"
        #  plot_edge e2, :color => "orange"
        #  show_plot
        #end

        # Find the distance from the destination node to the generator
        new_d = graph.manhattan_distance :from => dst_n, :to => gen.node

        [tgt, e2, e2.length + new_d]
      end.compact.filter {|_, e, _| e.possible? }

      tgt, e, new_dist = new_edges.min_by {|_, _, d| d }
      [src, tgt, e, new_dist]
    end

    new_edges
  end

  # How far away are two connected graphs?
  def group_distance(cg1, cg2)
    graph.manhattan_distance :from => cg1.median_node, :to => cg2.median_node
  end

  # The `node` we're connecting to (we need to know the paths)
  # The `gens` that still have available capacity
  def fractional_share(node, gens)
    options   = gens.map {|g| g.path_to node }
  
    # This is to get the proper ratios
    # derived from the formula for parallel resistors
    fractions = options.map {|p| 1.0 / p.length }
    fractions = fractions.map {|f| f / fractions.sum }
  
    # {gen => [path, frac]}
    gens.zip(options.zip(fractions)).to_h
  end

  # the `#max` is for FP errors
  # I'm relying on my knowledge of math and the system to claim the invariant
  # that the value will always be >= 0, and anything less is a FP error
  def transmission_losses(path, demand)
    path.map do |e|
      [e, [e.power_loss(@flows[e] + demand) - @losses[e], 0].max]
    end
  end

  # Okay, take 3 or 4 or whatever.
  #
  # Each laod makes a demand for power from each generator based on the
  # resistance of each path (using the length of the line as an analog -- should
  # prolly make a wrapper method for this calculation so that in the future I can
  # alter it if need be).
  #
  # Each generator looks at the total demands placed against it and then
  # responds with the proportional amount based on how much power it can supply.
  #
  # Thus, in an uneven system, EVERY load will not be fully fed, and thus have
  # some remainder of unsatisfied demand.
  #
  # This total unsatisfied demand is then pumped into an equation that will
  # calculate the frequency drop on the system (https://electronics.stackexchange.com/a/546988)
  def calculate_flows!
    # Grouping the generator info.
    # {gen => [node, demand, path]}
    groups = Hash.new {|h, k| h[k] = [] }

    @loads.each do |node|
      # {gen => [path, frac]}
      fracs = fractional_share node, generators
      fracs.each do |gen, (path, frac)|
        groups[gen] << [node, node.load * frac, path]
      end
    end
  
    # Since now we're going to track the flow through EVERY node-gen path,
    # we don't need to do any checks.
    # 
    # Since we're visiting all of the loads, we *don't* need to subtract the
    # generator's self-load from their power -- it'll happen.
    # 
    # When a generator doesn't have power... that's too bad, it still supplies it,
    # but the overall frequency of the system will drop
  
    # => {edge => flow}
    @flows    = Hash.new {|h, k| h[k] = 0 }
  
    # TODO FIXME actually fill out these values
    # => {edge => transmission losses}, so we only recalculate the ones we need
    @losses   = Hash.new {|h, k| h[k] = 0 }

    # Load remainder
    l_remainder = @loads.map {|l| [l, l.load] }.to_h

    groups.each do |gen, demands|
      total_demand = demands.sum {|n, l, p| l }

      # grow or shrink factor (if the load is insufficient, then the frequency
      # will increase)
      ratio = gen.power / total_demand

      demands.each do |node, demand, path|
        l_remainder[node] -= demand * ratio

        # Update the flow
        path.each do |edge|
          @flows[edge] += demand * ratio
        end
      end
    end

    # Transmission loss is a price that *will* be paid.
    @flows.each do |edge, flow|
      @losses[edge] = edge.power_loss flow
    end

    # power of the load is the nodes plus tx loss
    p_l = @loads.sum(&:load) + @losses.values.sum

    # rated power (of the generators)
    p_r = generators.sum {|g| g.power }

    @freq = freq_drop(p_l, p_r)
  end

  # https://electronics.stackexchange.com/a/546988
  # No idea if I did this right
  def freq_drop(p_l, p_r, droop=0.05, k_lr=0.02, f_s=BASE_FREQ)
    d_p = p_r - p_l.to_f # positive is load is less than generation

    d_f = d_p / ((p_r / (f_s * droop)) + p_l * k_lr)
    d_f
  end

  def flow_info(n=5)
    str = ""

    max, min = flows.values.max || 0, flows.values.min || 0
    #max, min = (nodes.size / 6).round(1), 1
    splits = n.times.map {|i| (max - min) * i / n.to_f + min }
    splits = [*splits, [flows.values.max || 0, max].max + 1]

    max, min = 100, 0
    legend = n.times.map {|i| (max - min) * i / n.to_f + min }
    legend = [*legend, max]

    # low to high, because that's how splits is generated
    percentiles = splits.each_cons(2).map do |bottom, top|
      flows.filter {|e, f| f >= bottom && f < top }.size
    end

    percentiles.zip(legend.each_cons(2))
               .zip(splits.each_cons(2))
               .each do |(pc, legend), (bottom, top)|
      str << "\t#{legend[0].round}-#{legend[1].round}%\t(#{bottom.round(1)}-#{top.round(1)}):\t#{pc}\n"
    end

    str << "\tMin, max: #{[flows.values.min, flows.values.max]}"
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
    str << "\tFrequency: #{BASE_FREQ + freq.round(2)} Hz (#{freq.round 2} Hz)\n"
    str << "\tPower: #{power} (#{generators.size} gens)\n"
    str << "\t\t#{generators.map {|g| g.power }}\n"
  end
end

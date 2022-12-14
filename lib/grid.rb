class Grid
  # Constraints, in one place
  MAX_BUILD_POWER = 150 # units of power
  MAX_GROW_POWER  = 120
  THRESHOLD_FOR_BUILD = 50

  attr_accessor :nodes
  attr_accessor :generators
  attr_accessor :graph
  attr_accessor :reach
  attr_accessor :flows
  attr_accessor :losses

  def initialize(nodes, generators)
    @nodes      = nodes
    @generators = generators
    @graph      = ConnectedGraph.new nodes
    @reach      = DisjointGraph.new []
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

  def reset!
    graph.invalidate_cache!
    calculate_flows!
  end

  def nearest_generator(node)
    generators.min_by {|g| graph.manhattan_distance :from => node, :to => g.node }
  end

  def build_generators_for_unreached(nodes_per_cluster)
    connected_graphs = unreached.connected_subgraphs

    biguns = connected_graphs.filter {|cg| cg.size > THRESHOLD_FOR_BUILD }

    old_size = generators.size

    biguns.each do |graph|
      pwr = [nodes_per_cluster, MAX_BUILD_POWER].min
      @generators += graph.generators_for_clusters(self, pwr) do |num|
        (num.to_f / nodes_per_cluster).ceil
      end
    end

    calculate_flows!

    generators.size - old_size
  end

  def grow_generators_for_unreached
    connected_graphs = unreached.connected_subgraphs

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

  def connect_generators(gen_1, gen_2)
    groupings = graph.nodes.group_by {|n| nearest_generator n }

    cg1 = ConnectedGraph.new groupings[gen_1]
    cg2 = ConnectedGraph.new groupings[gen_2]

    connect_graphs cg1, cg2
  end

  def connect_graphs(cg1, cg2)
    # Get the list of possible edges
    # Filter to only include those that don't currently exist
    # Sort with the shortest distance first
    rankings = cg1.nodes.product(cg2.nodes).map do |a, b|
      [a, b, a.euclidean_distance(b)]
    #end.filter {|a, b, d| not a.edge?(b) }.sort_by {|_, _, v| v }
    end.sort_by {|_, _, v| v }

    # TODO revert this bullshit. not build an edge? get outta here
    #
    # This returns and does nothing if the edge already exists.
    # What we *should* do is find the next best edge and connect that.
    return if rankings[0][0].edge? rankings[0][1]

    # DON'T mark the nodes -- simply provide the edge that accomplishes the mission.
    Edge.new rankings[0][0], rankings[0][1], rankings[0][2]
  end

  # How far away are two connected graphs?
  def group_distance(cg1, cg2)
    graph.manhattan_distance :from => cg1.median_node, :to => cg2.median_node
  end

  def calculate_flows!
    # Now that we know that everyone is connected (because we're dealing with
    # `grid.reach`), we get to sorta sort everyone by the generator that they're
    # closest to
    #
    # Actually, this is going to be a lot like the MST algorithm
    neighbors = []
    nodes.each do |node|
      generators.each do |gen|
        neighbors << [node, gen, gen.path_to(node)]
      end
    end

    # Now -- just like in the MST algorithm -- we're going to sort them
    # and put them into the tree, provided two conditions are met:
    #   1. we haven't already added a path for that node
    #   2. the generator still has some juice left
    #
    # Remember: we already know this graph is going to be connected, so we
    # don't have to worry about revisiting nodes in case we can suddenly reach them
    #
    # Also: since we're visiting all of the nodes, we *don't* need to start off
    # by subtracting the generator's self-load from their power. This is contrary
    # to (the now-deleted) `#calculate_reach!`, which uses
    # `#traverse_edges_in_phases`, which won't visit the sources (generators'
    # nodes).
    #
    # Damn. I really gotta have faith that this made-up algorithm is correct.
    visited   = Set.new
    @flows    = Hash.new {|h, k| h[k] = 0 }

    # {edge => transmission losses}, so we only recalculate the ones we need
    @losses   = Hash.new {|h, k| h[k] = 0 }
    remainder = generators.map {|g| [g, g.power] }.to_h

    neighbors.sort_by {|n, g, p| p.size }.each do |node, gen, path|
      next if visited.include? node
      
      # Compute the power losses here so we can decide if we can even afford to
      # take on this new node
      tx_losses = path.map {|e| [e, e.power_loss(@flows[e] + node.load) - @losses[e]] }

      next if remainder[gen] < (node.load + tx_losses.sum {|e, l| l })

      remainder[gen] -= node.load
      path.each {|e| @flows[e] += node.load }

      # Reuse the already-calculated transmission losses
      tx_losses.each {|e, l| @losses[e] = l }

      visited << node
    end

    @reach = DisjointGraph.new visited.to_a

    #@losses = @flows.sum {|edge, flow| edge.power_loss flow }.round 5

    #puts "\tGenerators with remainders:"
    #print "\t["
    #remainder.each do |gen, rem|
    #  next if rem == 0
    #  puts "\t\t#{gen.node.to_a.map {|v| v.round(2) }} [#{gen.power}] => #{rem}"
    #end
    #puts "]"

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
    str << "\tPower required: #{nodes.sum {|n| n.load }}\n"
    total_load = reach.load + losses.values.sum
    str << "\tReach load: #{total_load.round 2}\n"
    str << "\t\tNodes: #{reach.load}\n"
    str << "\t\tTx losses: #{losses.values.sum.round(2)} "
    str <<      "(#{(100 * losses.values.sum / reach.load.to_f).round 2}%)\n"
    efficiency = total_load / power.to_f
    str << "\tEfficiency: #{efficiency}\n"
    str << "\tPower: #{power} (#{generators.size} gens)\n"
    str << "\t\t#{generators.map {|g| g.power }}\n"
    str << "\tReached: #{reach.size}\n"
    str << ("\tUnreached: #{unreached.size} " +
            "(#{unreached.connected_subgraphs.size} subgraphs)\n")
    str << "\t\t#{unreached.connected_subgraphs.map {|cg| cg.size }}"
  end
end

module Flow
  BASE_FREQ = 60 # Hz

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

  # Find the two closest nodes between the two CGs and draw a straight line
  # between them
  def connect_graphs(cg1, cg2)
    # Get the list of possible edges
    # Sort with the shortest distance first
    # (we check later on to see if the edge already exists)
    closest = cg1.nodes.product(cg2.nodes).map do |a, b|
      [a, b, a.euclidean_distance(b)]
    end.min_by {|_, _, v| v }

    # DON'T mark the nodes -- simply provide the edge that accomplishes the mission.
    [Edge.new(closest[0], closest[1], closest[2], :id => PRNG.rand),
     closest[0],
     closest[1]]
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
    new_edges = bounds.parallel_map do |src, dist|
    #new_edges = bounds.map do |src, dist|
      new_edges = generators.map do |gen|
        # fuck it, dist - 1 is made up
        # How do we *actually* know whether we've sufficiently expanded a group
        # in our attempts to connect to it?
        tgt = ConnectedGraph.new([gen.node]).expand :steps => (dist - 3)

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

    convert_from_parallel new_edges

    new_edges
  end

  # The nodes get copied across processes during parallelization, and so
  # while all of their details may be correct, they'll refer to the wrong
  # objects, so we need to ensure that the references point to the nodes in *this*
  # process.
  def convert_from_parallel(edges)
    edges.each do |_, _, edge|
      edge.nodes = edge.nodes.map {|n| @map[n.id] }
    end
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
end


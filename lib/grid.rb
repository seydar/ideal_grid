class Grid
  attr_accessor :nodes
  attr_accessor :generators
  attr_accessor :graph
  attr_accessor :reach
  attr_accessor :flows

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

  def calculate_reach!
    # This is here for plotting purposes. For some reason it fails when I move
    # it to `initialize`.
    @reach = DisjointGraph.new(generators.map {|g| g.node })

    remainders = Hash.new {|h, k| h[k] = 0 }
    generators.each {|g| remainders[g.node] = g.power - g.node.load }

    reach = UnionF.new nodes
    touching = []

    dec_remainders = proc do |edge, from, to|
      if remainders[reach.find from] >= to.load
        touching << edge
        remainders[reach.find from] -= to.load

        true  # proceed down the rest of this branch
      else
        false # don't proceed down this branch just yet
      end
    end

    i = 0

    # join these remainders
    join_sources = proc do |visited|
      if $intermediate
        plot_grid self, :reached
        plot_edges visited, :color => "purple"
        save_plot "images/#{i}.png"
      end
      i += 1

      touching.map do |edge|
        s1, s2 = *edge.nodes

        # We don't know who is going to be the root in the UnionFind, so we're
        # preparing by getting the total now.
        total = remainders[reach.find s1] + remainders[reach.find s2]

        # smaller gets joined to the bigger (bigger becomes root)
        # If they're equal, then s1 is the root
        reach.union s1, s2 

        # Okay, now we can get the root and give it the proper remainder
        remainders[reach.find s1] = total
      end

      touching.clear # due to scoping and proc bindings, we need to clear this here
    end

    sources = generators.map {|g| g.node }
    visited = graph.traverse_edges_in_phases sources, dec_remainders, join_sources

    puts "\tsaved #{i} images" if $intermediate

    reachable = visited.map {|e| e.nodes }.flatten.uniq
    @reach = DisjointGraph.new reachable
  end

  def build_generators_for_unreached(clusters_per_subgraph)
    connected_graphs = unreached.connected_subgraphs

    biguns = connected_graphs.filter {|cg| cg.size >  50 }

    biguns.each do |graph|
      pwr = [graph.size / clusters_per_subgraph, 50].min
      @generators += graph.generators_for_clusters(self, pwr) { clusters_per_subgraph }
    end

    calculate_reach!

    biguns.size
  end

  def grow_generators_for_unreached
    connected_graphs = unreached.connected_subgraphs

    liluns = connected_graphs.filter {|cg| cg.size <= 50 }

    liluns.each do |graph|
      nearest_gen = generators.min_by {|g| graph.manhattan_distance_from_group g.node }
      nearest_gen.power += graph.nodes.size
    end

    calculate_reach!

    liluns.size
  end

  def calculate_flows!
    # Now that we know that everyone is connected (because we're dealing with
    # `grid.reach`), we get to sorta sort everyone by the generator that they're
    # closest to
    #
    # Actually, this is going to be a lot like the MST algorithm
    neighbors = []
    reach.nodes.each do |node|
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
    visited   = Set.new
    @flows    = Hash.new {|h, k| h[k] = 0 }
    remainder = generators.map {|g| [g, g.power - g.node.load] }.to_h

    neighbors.sort_by {|n, g, p| p.size }.each do |node, gen, path|
      next if visited.include? node
      next if remainder[gen] < node.load

      remainder[gen] -= node.load
      path.each {|e| @flows[e] += 1 }
    end
  end
end

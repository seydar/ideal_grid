class Grid
  attr_accessor :nodes
  attr_accessor :generators
  attr_accessor :graph
  attr_accessor :reach

  def initialize(nodes, generators)
    @nodes      = nodes
    @generators = generators
    @graph      = ConnectedGraph.new nodes
    @reach      = DisjointGraph.new(generators.map {|g| g.node })
  end

  def analyze
    reach.connected_subgraphs.map do |cg|
      applicable_generators = generators.filter {|g| cg.nodes.include? g.node }
      Analyzer.new cg, applicable_generators
    end
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

  # FIXME with disjoint reaches (where generator reaches don't touch), some
  # generators can accidentally claim more than their fair share, so you'll
  # end up with a subgraph that has 12 nodes but a generator power of only 10:
  #   # ./grid.rb -n 50 -c 2
  #
  # Start by simultaneously calculating the reaches for each generator.
  # Then, when two graphs become connected, join their remainders.
  # Continue checking graphs even when their remainder is zero.
  #
  # From Keir:
  #   "Start with potential, which will tell you the direction of flow, and
  #    then determine the amps."
  def old_calculate_reach!
    reachable = generators.map {|g| g.node }
    loads     = generators.map {|g| g.node.load }.sum
    remainder = power - loads

    if remainder < 0
      raise "Generators can't power themselves (node.load > gen.power across all gens)"
    end

    # Start with the generator nodes as the sources
    graph.traverse_nodes reachable do |edge, from, to|
      if remainder - to.load >= 0
        reachable << to
        remainder -= to.load
      end
    end

    # Not necessarily a connected subgraph!
    @reach = DisjointGraph.new reachable
  end

  def calculate_reach!
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
      plot_grid self, :reached
      plot_edges visited, :color => "purple"
      save_plot "images/#{i}.png"
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

    reachable = visited.map {|e| e.nodes }.flatten.uniq
    @reach = DisjointGraph.new reachable
  end
end

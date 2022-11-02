class Grid
  attr_accessor :nodes
  attr_accessor :generators
  attr_accessor :graph
  attr_accessor :reach

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

    reachable = visited.map {|e| e.nodes }.flatten.uniq
    @reach = DisjointGraph.new reachable
  end
end

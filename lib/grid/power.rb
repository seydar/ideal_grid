module Power
  MAX_BUILD_POWER     = 300 # units of power
  MAX_GROW_POWER      = 200
  THRESHOLD_FOR_BUILD = 20

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
end


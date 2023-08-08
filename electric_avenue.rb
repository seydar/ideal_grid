require_relative 'lib/monkey_patch.rb'
Dir['./lib/**/*.rb'].each {|f| require_relative f }

# Handy helper methods to get started
#
# `number` is the number of nodes
# `grouping` is the number of nodes per generator
# `range` is how big the scene is: x and y are 0-`range`
def mst_grid(number: nil, grouping: nil, range: 10)
  nodes = number.times.map do |i|
    n = Node.new(range * PRNG.rand, range * PRNG.rand, :id => i)
    n.load = 1
    n
  end

  pairs = nodes.combination 2
  edges = pairs.map.with_index do |(p_1, p_2), i|
    Edge.new p_1,
             p_2,
             p_1.euclidean_distance(p_2),
             :id => i
  end

  mst = []

  # Builds edges between nodes according to the MST
  parallel_filter_kruskal edges, UnionF.new(nodes), mst

  # Give edges new IDs so that they are 0..|edges|
  edges = nodes.map(&:edges).flatten.uniq
  edges.each.with_index {|e, i| e.id = i }

  grid = Grid.new nodes, []

  # FIXME does this really need to be a separate graph?
  graph = ConnectedGraph.new grid.nodes

  # Needed for the global adjacency matrix for doing faster manhattan distance
  # calculations
  KMeansClusterer::Distance.graph = graph
  
  grid.build_generators_for_unreached grouping

  grid
end


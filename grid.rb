require 'math'
require 'gnuplot'

class Point
  attr_accessor :x
  attr_accessor :y
  attr_accessor :visited

  def initialize(x, y)
    @x, @y = x, y
  end
end

class Edge
  attr_accessor :to
  attr_accessor :from
  attr_accessor :weight
  attr_accessor :explored

  def initialize(to, from, weight=0)
    @to, @from, @weight = to, from, weight
  end
end

def dist(p_1, p_2)
  Math.sqrt((p_1.x - p_2.x) ** 2 + (p_1.y - p_2.y) ** 2)
end

# Kruskal's algorithm for an MST
# https://github.com/mneedham/algorithms2/blob/master/kruskals.rb
def has_cycles(edge)
  node_1, node_2 = edge.from, edge.to
  @minimum_spanning_tree.each {|x| x.explored = false }
  cycle_between node_1, node_2, @minimum_spanning_tree
end

def cycle_between(one, two, edges)
  adjacent_edges = edges.filter {|e| [e.to, e.from].include? one }
  return false if adjacent_edges.empty?

  adjacent_edges.select {|e| not e.explored }.each do |edge|
    edge.explored = true
    other = (edge.from == one) ? edge.to : edge.from

    return true if other == two || cycle_between(other, two, edges)
  end

  false
end

# Generate a bunch of random points
points = 10.times.map { Point.new(10 * rand, 10 * rand) }
edges  = points.combination(2).map {|p_1, p_2| Edge.new p_1,
                                                        p_2,
                                                        dist(p_1, p_2) }

@minimum_spanning_tree = []
edges.each do |edge|
  @minimum_spanning_tree << edge unless has_cycles edge
end


############################
plt = Numo::Gnuplot.new
xs, ys = points.map {|p| p.x }, points.map {|p| p.y }
#plt.plot xs, ys, :with => 'lines'

#@minimum_spanning_tree.each do |edge|
#  plt.plot [edge.from.x, edge.to.x], [edge.from.y, edge.to.y], :with => 'lines'
#end

pts = @minimum_spanning_tree.map {|e| [[e.from.x, e.to.x], [e.from.y, e.to.y]] }
plt.plot 

gets


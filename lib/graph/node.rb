class Node
  attr_accessor :x
  attr_accessor :y
  attr_accessor :visited
  attr_accessor :edges

  # Needed to judge node equality after serialization
  attr_accessor :id # for multiprocess synchronization

  def initialize(x, y)
    @x, @y = x, y
    @edges = []
  end

  def inspect
    "#<Node:#{object_id} @x=#{x.round 3}, @y=#{y.round 3}, # of edges=#{edges.size}>"
  end

  def other_nodes_connected_to_not(except)
    branches = edges - [except]
    branches.map do |b|
      (b.nodes - [self])[0].other_nodes_connected_to_not b
    end.sum + 1
  end

  def euclidean_distance(p_2)
    Math.sqrt((self.x - p_2.x) ** 2 + (self.y - p_2.y) ** 2)
  end

  # No guarantee that path is shortest
  # Actually, we *are* guaranteed that because we're using a MST
  def path_to(p_2, prev=nil)
    edges.each do |edge|
      # Don't go back the way we came
      next if edge == prev

      if edge.not_node(self) == p_2
        return [edge]
      else
        path = edge.not_node(self).path_to p_2, edge
        return (path << edge) unless path.empty?
      end
    end

    []
  end

  def edge_distance(other)
    Path.build(path_to(other)).weight
  end

  def dist(p_2, style=:euclidean)
    case style
    when :edges
      edge_distance p_2
    when :euclidean
      euclidean_distance p_2
    else
      raise "No style provided for distance calculation"
    end
  end

  def to_a
    [x, y]
  end
end


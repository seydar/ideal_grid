class Node
  attr_accessor :x
  attr_accessor :y
  attr_accessor :visited
  attr_accessor :edges
  attr_accessor :load
  attr_accessor :id

  def initialize(x, y, id: nil)
    @x, @y = x, y
    @edges = []
    @load  = nil
    @id    = id
  end

  def inspect
    "#<Node:#{object_id} @x=#{x.round 3}, @y=#{y.round 3}, # of edges=#{edges.size}>"
  end

  def count_accessible_branches(except=nil, &blk)
    branches = edges - (except ? [except] : [])
    branches.map do |b|
      (b.nodes - [self])[0].count_accessible_branches(b, &blk)
    end.sum + blk.call(except, self)
  end
  
  def total_nodes
    count_accessible_branches do |_, _|
      1
    end
  end
  
  def total_edge_length
    count_accessible_branches do |edge, _|
      edge.length
    end
  end
  
  def total_node_loads
    count_accessible_branches do |_, node|
      node.load
    end
  end

  def euclidean_distance(p_2)
    Math.sqrt((self.x - p_2.x) ** 2 + (self.y - p_2.y) ** 2)
  end

  # No guarantee that path is shortest
  # Actually, we *are* guaranteed that because we're using a MST
  def path_to(p_2, prev=nil)
    return [] if p_2 == self

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
    Path.build(path_to(other)).length
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

  def ==(other)
    return false unless other.is_a? Node
    id == other.id
  end
end


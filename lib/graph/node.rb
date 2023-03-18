class Node
  attr_accessor :x
  attr_accessor :y
  attr_accessor :edges
  attr_accessor :load
  attr_accessor :id
  attr_accessor :sources
  attr_accessor :point

  def initialize(x, y, id: nil, draws: 1, point: nil)
    raise "Don't be a fool — supply an ID" unless id

    @x, @y = x, y
    @edges = []
    @load  = draws
    @id    = id
    @sources = []
    @point = point
  end

  def inspect
    "#<Node:#{object_id} @x=#{x.round 3}, @y=#{y.round 3}, # of edges=#{edges.size}>"
  end

  def count_accessible_branches(except: nil, &blk)
    branches = edges - (except ? [except] : [])
    branches.map do |b|
      b.not_node(self).count_accessible_branches(:except => b, &blk)
    end.sum + blk.call(except, self)
  end
  
  def total_nodes(except: nil)
    count_accessible_branches :except => except do |_, _|
      1
    end
  end
  
  def total_edge_length(except: nil)
    count_accessible_branches :except => except do |edge, _|
      edge.length
    end
  end
  
  def total_load(except: nil)
    count_accessible_branches :except => except do |_, node|
      node.load
    end
  end

  def euclidean_distance(p_2)
    Math.sqrt((self.x - p_2.x) ** 2 + (self.y - p_2.y) ** 2)
  end

  # No guarantee that path is shortest
  # Actually, we *are* guaranteed that because we're using a MST
  #
  # I wonder how much of a drag this method is. Could using the adjacency
  # matrix in `Graph` be faster? Yes. Is it worth it? TBD.
  # 
  # Edit: turns out it's not that much slower than an adjacency matrix
  def path_to(p_2, history=[])
    return [] if p_2 == self

    p edges.size
    edges.each do |edge|
      # Don't go back the way we came
      next if history.include? edge
      print "\t"; p edge

      # this will be shared across all calls with this initialization
      # but I think that'll be okay
      history << edge

      if edge.not_node(self) == p_2
        return [edge]
      else
        #puts "#{to_a} => #{edge.not_node(self).to_a} (#{p_2.to_a})"
        path = edge.not_node(self).path_to p_2, history
        return (path << edge) unless path.empty?
      end
    end

    []
  end

  def edge?(other)
    edges.any? {|e| e.nodes.include? other }
  end

  # For some reason, the shitty method is faster than the
  # adjacency matrix method. Hm. Weird.
  def manhattan_distance(other)
    Path.build(path_to(other)).edges.size
  end

  def to_a
    [x, y]
  end

  def ==(other)
    return false unless other.is_a? Node
    id == other.id
  end
end


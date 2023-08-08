class Node
  # This... unfortunately prevents you from handling multiple grids at the
  # same time
  #@@distances = Hash.new {|h, k| h[k] = {} }

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

  def within?(bounds)
    x > bounds[:w] &&
      x < bounds[:e] &&
      y < bounds[:n] &&
      y > bounds[:s]
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

  # I hate that I had to optimize this weirdly, but I'm trying to make these
  # things faster, and I managed to get a 20% speedup by doing this.
  # 
  # FIXME this doesn't even use the memoization?????
  # The memoization hash should be bound to the host grid
  def euclidean_distance(p_2)
    dist = Math.sqrt((self.x - p_2.x) ** 2 + (self.y - p_2.y) ** 2)

    #@@distances[self.id][p_2.id] ||= dist
    #@@distances[p_2.id][self.id] ||= dist
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


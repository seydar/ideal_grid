class Edge
  attr_accessor :nodes # guaranteed to be #size == 2
  attr_accessor :length
  attr_accessor :explored
  attr_accessor :id
  
  attr_accessor :flow

  def initialize(to, from, length=0, id: nil)
    @length = length
    @nodes  = [to, from]
    @id     = id
    @flow   = {}
  end

  def mark_nodes!
    nodes.each {|n| n.edges << self }
  end
  
  def flow(from: nil, restrict: nil)
    return @flow[from] if @flow[from]

    other_node  = not_node from
    other_edges = other_node.edges - [self]
    
    return 0 unless restrict.include? other_node

    # base case
    if other_edges.empty?
      @flow[from] = other_node.load
    else
      @flow[from] = other_edges.map do |edge|
        edge.flow(:from => other_node, :restrict => restrict)
      end.sum + other_node.load
    end
  end

  def not_node(node)
    (nodes - [node])[0]
  end

  def inspect
    n1 = nodes[0].to_a.map {|v| v.round 3 }
    n2 = nodes[1].to_a.map {|v| v.round 3 }
    "#<Edge:#{object_id} #{n1} <=> #{n2}>"
  end

  def ==(other)
    return false unless other.is_a? Edge
    id == other.id
  end
end


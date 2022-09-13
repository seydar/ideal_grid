class Edge
  attr_accessor :nodes # guaranteed to be #size == 2
  attr_accessor :weight
  attr_accessor :explored

  def initialize(to, from, weight=0)
    @weight = weight
    @nodes  = [to, from]
  end

  def mark_nodes!
    nodes.each {|n| n.edges << self }
  end

  def other_node(node)
    (nodes - [node])[0]
  end
  alias_method :not_node, :other_node

  def inspect
    n1 = nodes[0].to_a.map {|v| v.round 3 }
    n2 = nodes[1].to_a.map {|v| v.round 3 }
    "#<Edge:#{object_id} #{n1} <=> #{n2}>"
  end

  def ===(other)
    nodes.map(&:to_a) === other.nodes.map(&:to_a) &&
      weight == other.weight &&
      explored == other.explored
  end
end


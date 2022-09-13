class Path
  attr_accessor :edges
  attr_accessor :nodes

  def self.build(edges)
    path = new edges
    path.sort_points!

    path
  end

  def weight
    edges.map {|e| e.weight }.sum
  end

  def initialize(edges)
    @edges = edges
    @nodes = []
  end

  def sort_points!
    sorted = []

    if edges.size == 1
      @nodes = edges[0].nodes
      return
    end

    edges.each.with_index do |edge, i|
      if edges[i + 1]
        unique = edge.nodes - edges[i + 1].nodes # unique node to `edge`
        sorted << unique[0]
      else # we're at the last one
        unique = edge.nodes - edges[i - 1].nodes
        sorted << (edge.nodes - unique)[0]
        sorted << unique[0]
      end
    end

    @nodes = sorted
  end

  # Median by the number of edges, but not by weight
  # n edges, n + 1 nodes
  def median
    #nodes[nodes.size / 2]
    total = 0
    edges.each.with_index do |edge, i|
      total += edge.weight

      if total > weight / 2.0
        # return whichever one is closer: this node or the next
        if total - weight < edge.weight / 2.0
          return nodes[i + 1]
        else
          return nodes[i]
        end
      end
    end

    p total
    p edges
    raise "something went wrong in calculating the median"
  end

  def size
    edges.inject(0) {|s, e| s + e.weight }
  end
  alias_method :length, :size
end


class Path
  attr_accessor :edges
  attr_accessor :nodes

  def self.build(edges)
    path = new edges
    path.sort_points!

    path
  end

  def initialize(edges)
    @edges = edges
    @nodes = []
  end

  # Edges are in order, but their points are not necessarily. In addition,
  # they'll repeat points (edge X is from A - B, edge Y is B - C, so you can't
  # just map all the points together)
  def sort_points!
    sorted = []

    if edges.size == 1
      @nodes = edges[0].nodes
      return
    end

    edges.each.with_index do |edge, i|
      if edges[i + 1] # if we're not the last node
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

  # n edges, n + 1 nodes
  def partition(threshold)
    total = 0

    edges.each.with_index do |edge, i|
      total += edge.length

      # if total > weight / 2.0
      if total > length * threshold
        # return whichever one is closer: this node or the next
        if total - length < edge.length * threshold
          return nodes[i + 1]
        else
          return nodes[i]
        end
      end
    end

    raise "something went wrong in calculating the median"
  end

  def median
    partition 0.5
  end

  def size
    @size ||= edges.inject(0) {|s, e| s + e.length }
  end
  alias_method :length, :size
end


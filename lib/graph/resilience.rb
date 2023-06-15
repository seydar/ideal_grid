# "A Graph Resilience Metric Based On Paths: Higher Order Analytics With GPU"
# Georgios Drakopoulos, 2018

module Resilience
  P_0 = 3

  # Final metric is J()
  # `s` here means that we're running the sigma function on every vertex
  # in the graph, and then we take that and calculate the max and min sigmas
  #
  # J(mu) | min(sigma(s, mu)) == 0 = 0
  #       | otherwise              = max(sigma(s, mu)) / min(sigma(s, mu))
  def j(mu)
    sigmas = nodes.map {|s| sigma(s, mu) }

    if sigmas.min == 0
      0
    else
      sigmas.max / sigmas.min
    end
  end

  # Convex combination of two factors:
  #   (# of paths of length p that pass through v) / 
  #     (# of paths of length p)
  #   and
  #   # of triangles that include v /
  #     # of triangles
  #
  # It kinda looks like we're measuring both connectedness of each node,
  # as well as comparing it to a triangle (which admittedly feels arbitrary)
  def sigma(v, mu)
    walk_node  = (3..P_0).map {|p| count_walks_thru v, :length => p }.avg
    walk_total = (3..P_0).map {|p| count_walks :length => p         }.avg
    walk_ratio = walk_node / walk_total.to_f

    triangle_ratio = count_triangles_from(v) / count_triangles

    mu * walk_ratio + (1 - mu) * triangle_ratio
  end

  # Walks are not paths! Walks can revisit nodes, whereas paths cannot
  def walk_matrix(n)
    @walks    ||= []
    @walks[n] ||= adjacency_matrix ** n
  end

  def count_walks_thru(v, length: 3)
    # Ever the mystery...
  end

  def count_walks_from(v, length: 3)
    walk_matrix(length).row(v.id).sum
  end

  def count_walks(length: 3)
    walk_matrix(length).row_vectors.sum {|row| row.sum }
  end

  def count_triangles_from(v)
    walk_matrix(3)[v.id, v.id]
  end

  def count_triangles
    walk_matrix(3).row_size.sum do |i|
      walk_matrix(3)[i, i]
    end / 3 # because of triple counting
  end

  # Alternate resilience metric
  def estrada
    # only keep the eigenvalues, which are the diagonals of the matrix `d`
    _, d, _ = adjacency_matrix.eigensystem
    d.map.with_index {|i| Math.exp d[i] }.sum
  end
end


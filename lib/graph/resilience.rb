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
  def j(mu, srcs=nil)
    # Prepping this calculation in advance of the parallelization
    paths :sources => srcs

    # Now we can actually do the parallelization and have `@paths` be copied
    # to the child processes
    sigmas = nodes.parallel_map {|v| sigma(v, mu) }

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
    path_node  = (3..P_0).map {|p| count_paths_thru v, :length => p }.avg
    path_total = (3..P_0).map {|p| count_paths :length => p         }.avg
    path_ratio = path_node / path_total.to_f

    triangle_ratio = count_triangles_from(v) / count_triangles
    triangle_ratio = 0.0 if triangle_ratio.nan? # what if no triangles?

    mu * path_ratio + (1 - mu) * triangle_ratio
  end

  # Walks are not paths! Walks can revisit nodes, whereas paths cannot
  #
  # Recursion and memoization because I'm a beast who knows no bounds
  def walk_matrix(n, sources: nil)
    @walks    ||= []

    if n == 1
      if sources
        puts "trying the new thing"
        # we start at the generators, but can then go anywhere
        @walks[n] ||= source_adjacency_matrix sources
      else
        @walks[n] ||= adjacency_matrix
      end
    else
      @walks[n] ||= adjacency_matrix * walk_matrix(n - 1)
    end
  end

  # P_v[1] * P_v[2] + P_v[3]
  #
  # Which says: (paths of length 1) TIMES (paths of length 2) PLUS (paths of length 3)
  # Because it's all combinations of 2 and 1
  #
  # I think? I kinda made that up based on reading a stack overflow answer
  # Man I wish I knew if any of this was right
  def count_paths_thru(v, length: P_0)
    pairs = (0..length).zip(length.downto(0)).map(&:sort).uniq
    pairs.sum do |left, right|
      count_paths_from(v, :length => left) * count_paths_from(v, :length => right)
    end
  end

  # P_v[n] = paths of length n starting from v
  def count_paths_from(v, length: P_0)
    return 0 if length <= 0
    paths(:length => length).row_vectors[@spots[v]].sum
  end

  # Only count the top-right diagonal half of the matrix
  # because it's duplicated (paths from i -> j is same as j -> i)
  def count_paths(length: P_0)
    total = 0
    mat   = paths :length => length
    mat.row_count.times do |i|
      (i..mat.row_count - 1).each do |j|
        total += mat[i, j]
      end
    end

    total
  end

  # P_3 = A^3 − (I ◦ A^2) · A − (I ◦ A^3) − A · (I ◦ A^2) + A
  # P_3[i, j] = # of paths from i to j
  #
  # Unfortunately, this isn't generalized yet, so we can only do length 3.
  # Dunno how to read the math in the paper. Too smoothbrained.
  def paths(length: P_0, sources: nil)
    return @mat_paths if @mat_paths

    rows = adjacency_matrix.row_size
    i = Matrix.identity rows
    a_3 = walk_matrix 3
    a_2 = walk_matrix 2
    a   = walk_matrix 1, :sources => sources

    @mat_paths = a_3 - i.hadamard_product(a_2) * a -
                   i.hadamard_product(a_3) -
                   a * i.hadamard_product(a_2) +
                   a
  end

  def count_triangles_from(v)
    walk_matrix(3)[@spots[v], @spots[v]]
  end

  def count_triangles
    walk_matrix(3).row_size.times.sum do |i|
      walk_matrix(3)[i, i]
    end / 3 # because of triple counting
  end

  # Alternate resilience metric
  def estrada
    # only keep the eigenvalues, which are the diagonals of the matrix `d`
    _, d, _ = adjacency_matrix.eigensystem
    d.each(:diagonal).map {|i| Math.exp i }.sum
  end
end


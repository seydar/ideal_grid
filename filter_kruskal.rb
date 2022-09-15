require './lib/unionf.rb'

# Procedure kruskal(E , T : Sequence of Edge, P : UnionFind)
def kruskal(edges, uf, mst=[])
  $algorithm ||= "Kruskal"

  # sort E by increasing edge weight
  edges = edges.sort_by {|e| e.weight }
  # foreach {u,v} ∈ E do
  edges.each do |edge|
    # if u and v are in different components of P then
    unless uf.connected? edge.nodes[0], edge.nodes[1]
      # add edge {u,v} to T
      mst << edge
      # join the partitions of u and v in P
      uf.union edge.nodes[0], edge.nodes[1]

      # This is part of the "join the partitions" step
      # Not sure what everyone else does for this part, but I need
      # to keep track of which nodes are connected to which other ones
      edge.mark_nodes!
    end
  end

  uf
end

####################################################33
# Edges m, Nodes n
# Resources:
#   https://github.com/allenchou/CMU-15618-Final-Project/blob/master/src/mst/kruskal_filter.cpp
#   http://algo2.iti.kit.edu/documents/algo1-2014/alenex09filterkruskal.pdf
#   http://algo2.iti.kit.edu/documents/fkruskal.pdf
#   https://en.wikipedia.org/wiki/Kruskal%27s_algorithm#Parallel_algorithm

SEQ_THRESHOLD = 8192 # stolen from the CMU students (Allen Chou)

# Sequential (but sets the tone for making it parallelizable)
#
# Procedure qKruskal(E, T : Sequence of Edge, P : UnionFind)
def qKruskal(edges, uf, mst=[])
  $algorithm = "qKruskal"

  # if m ≤ kruskalThreshold(n, |E|, |T|)
  if edges.size <= SEQ_THRESHOLD
    # then kruskal(E, T, P)
    kruskal edges, uf, mst
  # else
  else
    # pick a pivot p ∈ E
    pivot = edges.sample.weight
    # E≤ := ⟨e ∈ E :e ≤ p); E> := ⟨e ∈ E :e > p⟩
    es_l, es_g = edges.partition {|e| e.weight <= pivot }
    # qKruskal(E≤ , T , P )
    qKruskal es_l, uf, mst
    # qKruskal(E> , T , P )
    qKruskal es_g, uf, mst
  end

  uf
end

# Parallelizable
#
# Procedure filterKruskal(E, T : Sequence of Edge, P : UnionFind)
def filterKruskal(edges, uf, mst=[])
  $algorithm = "filter Kruskal"

  # if m ≤ kruskalThreshold(n, |E|, |T|)
  if edges.size <= SEQ_THRESHOLD
    # then kruskal(E, T, P) -- parallel (within sorting)
    kruskal edges, uf, mst
  # else
  else
    # pick a pivot p ∈ E
    pivot = edges.sample.weight
    # E≤ := ⟨e ∈ E :e ≤ p); E> := ⟨e ∈ E :e > p⟩
    es_l, es_g = edges.partition {|e| e.weight <= pivot }
    # filterKruskal(E≤, T, P)
    filterKruskal es_l, uf, mst
    # E> := filter(E>, P) -- parallel (remove_if)
    es_g = filter es_g, uf
    # filterKruskal(E>, T, P)
    filterKruskal es_g, uf, mst
  end

  uf
end

# Parallelizable
#
# Procedure filterKruskal(E, T : Sequence of Edge, P : UnionFind)
def parallel_filter_kruskal(edges, uf, mst=[])
  $algorithm = "parallel filter Kruskal"

  # if m ≤ kruskalThreshold(n, |E|, |T|)
  if edges.size <= SEQ_THRESHOLD
    # then kruskal(E, T, P) -- parallel (within sorting)
    kruskal edges, uf, mst
  # else
  else
    # pick a pivot p ∈ E
    pivot = edges.sample.weight
    # E≤ := ⟨e ∈ E :e ≤ p⟩; E> := ⟨e ∈ E :e > p⟩ -- parallel
    es_l, es_g = edges.parallel_partition {|e| e.weight <= pivot }
    # filterKruskal(E≤, T, P)
    parallel_filter_kruskal es_l, uf, mst
    # E> := filter(E>, P) -- parallel (remove_if)
    es_g = parallel_filter es_g, uf
    # filterKruskal(E>, T, P)
    parallel_filter_kruskal es_g, uf, mst
  end

  mst
end

# Function filter(E)
def filter(edges, uf)
  # return ⟨{u, v} ∈ E : u, v are in different components of P⟩
  edges.filter {|e| not uf.connected?(e.nodes[0], e.nodes[1]) }
end

# Function filter(E)
def parallel_filter(edges, uf)
  # return ⟨{u, v} ∈ E : u, v are in different components of P⟩
  edges.parallel_filter {|e| not uf.connected?(e.nodes[0], e.nodes[1]) }
end


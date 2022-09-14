
def has_cycles(edge, mst)
  node_1, node_2 = *edge.nodes
  mst.each {|x| x.explored = false }
  cycle_between node_1, node_2, mst
end

def cycle_between(one, two, edges)
  adjacent_edges = edges.filter {|e| e.nodes.include? one }
  return false if adjacent_edges.empty?

  adjacent_edges.select {|e| not e.explored }.each do |edge|
    edge.explored = true
    other = edge.nodes.find {|n| n != one } # `edge.nodes.size == 2`

    return true if other == two || cycle_between(other, two, edges)
  end

  false
end


# Procedure kruskal(E , T : Sequence of Edge, P : UnionFind)
def kruskal(edges, mst=[])
  #   sort E by increasing edge weight
  edges = edges.to_a.sort_by {|e| e.weight }
  #   foreach {u,v} ∈ E do
  edges.each do |edge|
  #     if u and v are in different components of P then
    unless has_cycles edge, mst
  #       add edge {u,v} to T
      mst << edge
  #       join the partitions of u and v in P
      edge.mark_nodes!
    end
  end
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
def qKruskal(edges, mst, uf)
  # if m ≤ kruskalThreshold(n, |E|, |T|)
  if edges.size <= SEQ_THRESHOLD
    # then kruskal(E, T, P)
    kruskal(edges, mst)
  # else
  else
    # pick a pivot p ∈ E
    pivot = edges.sample
    # E≤:= ⟨e ∈ E : e ≤ p⟩
    es_l = edges.filter {|e| e.weight <= pivot }
    # E>:= ⟨e ∈ E : e > p⟩
    es_g = edges.filter {|e| e.weight >  pivot }
    # qKruskal(E≤ , T , P )
    qKruskal es_l, mst, uf
    # qKruskal(E> , T , P )
    qKruskal es_g, mst, uf
  end
end

# Parallelizable
#
# Procedure filterKruskal(E, T : Sequence of Edge, P : UnionFind)
def filterKruskal(edges, mst=[], uf=UnionF.new)
  # if m ≤ kruskalThreshold(n, |E|, |T|)
  if edges.size <= SEQ_THRESHOLD
    # then kruskal(E, T, P) -- parallel (within sorting)
    kruskal(edges, mst)
  # else
  else
    # pick a pivot p ∈ E
    pivot = edges[edges.size / 2].weight
    # E≤ := ⟨e ∈ E :e ≤ p⟩ -- parallel (partition)
    es_1 = edges.filter {|e| e.weight <= pivot }
    # E> := ⟨e ∈ E :e > p⟩ -- parallel (partition)
    es_g = edges.filter {|e| e.weight >  pivot }
    # filterKruskal(E≤, T, P)
    filterKruskal es_l, mst, uf
    # E> := filter(E>, P) -- parallel (remove_if)
    es_g = filter es_g, uf
    # filterKruskal(E>, T, P)
    filterKruskal es_g, mst, uf
  end

  mst
end

# Function filter(E)
def filter(edges)
  # return ⟨{u, v} ∈ E : u, v are in different components of P⟩
  edges.filter {|e| not connected?(e.nodes[0], e.nodes[1]) }
end


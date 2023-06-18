require_relative 'graph.rb'

class DisjointGraph < Graph

  # There's an optimization in here, I'm sure, but I don't care to find it
  def connected_subgraphs
    uf    = UnionF.new nodes
    edges = nodes.map {|n| n.edges }.flatten
                 .filter {|e| (e.nodes - nodes).empty? }
  
    edges.each do |edge|
      # no-op if they're already unioned
      uf.union edge.nodes[0], edge.nodes[1]
    end
  
    uf.disjoint_sets.map {|djs| ConnectedGraph.new djs }
  end
end


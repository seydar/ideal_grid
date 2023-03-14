require_relative "../lib/graph/node.rb"
require_relative "../lib/graph/edge.rb"
require_relative "../lib/graph/graph.rb"

def circle(nodes)
  nodes.size.times do |i|
    e = Edge.new nodes[i],
                 nodes[(i + 1) % nodes.size],
                 nodes[i].euclidean_distance(nodes[(i + 1) % nodes.size])
    nodes[i].edges << e
    nodes[(i + 1) % nodes.size].edges << e
    #e.mark_nodes!
  end
end

nodes = 10.times.map {|i| Node.new rand, rand, i }

circle nodes

cg = ConnectedGraph.new nodes

require 'pry'
binding.pry


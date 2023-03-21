require_relative "../lib/graph/node.rb"
require_relative "../lib/graph/edge.rb"
require_relative "../lib/graph/graph.rb"
require_relative "../lib/monkey_patch.rb"

def circle(nodes)
  nodes.size.times do |i|
    e = Edge.new nodes[i],
                 nodes[(i + 1) % nodes.size],
                 nodes[i].euclidean_distance(nodes[(i + 1) % nodes.size]),
                 :id => i
    nodes[i].edges << e
    nodes[(i + 1) % nodes.size].edges << e
    #e.mark_nodes!
  end
end

nodes = 100.times.map {|i| Node.new rand, rand, :id => i }

circle nodes

cg = ConnectedGraph.new nodes
p cg.shortest_cycle

require 'pry'
binding.pry


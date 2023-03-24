#!/usr/bin/env ruby
require 'optimist'
require_relative '../electric_avenue.rb'

opts = Optimist::options do
  banner <<-EOS
Pretend a minimal electric grid is a minimum spanning tree across a bunch of nodes.
Now cluster them to determine where to put your generators.
Now add in extra edges to add resiliency.
Now calculate the capacity of each of the lines.

Usage:
  model.rb [options]
where [options] are:

EOS

  opt :nodes, "Number of nodes in the grid", :type => :integer, :default => 100
  opt :clusters, "How many nodes per generator", :type => :integer, :default => 10
  opt :intermediate, "Show intermediate graphics of flow calculation", :type => :integer
  opt :reduce, "How many times should we try to reduce congestion", :type => :integer, :default => 1
end

# NH/VT
NH_VT = {:n =>  44.1793, :s =>  43.8583,
         :e => -71.8985, :w => -72.2598}

# New England
NEW_ENGLAND = {:n =>  47.45, :s =>  40.94,
               :e => -66.85, :w => -73.45}

NEW_ENGLAND_CENTRAL = {:n =>  45.01, :s =>  42.71,
                       :e => -71.01, :w => -73.25}

# Michigan
MICHIGAN = {:n =>  45.82, :s =>  41.80,
            :e => -82.72, :w => -86.12}

# More numbers that are divinely inspired.
# Sometimes I close my eyes and just see where the keyboard takes me.
#
# But actually, these were derived from the 7/22/22 @ 19:07:02 fuel mix.
# Then I grouped them logically (since the categories don't *quite* fit)
# and multiplied them by 1.11 to account for potential transmission loss.
# I'll adjust these numbers as need be based on the transmission loss that
# #calculate_flows! interprets.
grid = Grid.within NEW_ENGLAND, :fuel => {:fossil  => 0.70,
                                          :nuclear => 0.17,
                                          :hydro   => 0.08,
                                          :biomass => 0.03,
                                          :solar   => 0.01,
                                          :wind    => 0.01}

puts "Grid: #{grid.inspect}"
grid.calculate_flows!

puts grid.info
puts grid.flow_info

plot_flows grid, :n => 10, :focus => :reached
show_plot

#added = []
#new_edges = grid.reduce_congestion
#
## TODO Are certain edges more effective than others? How do we know?
#added << []
#new_edges.each do |src, tgt, edge, dist|
#  if edge.length < 0.5
#    added[-1] << edge
#    edge.mark_nodes!
#  end
#end
#
#puts "New edges: #{added[-1].size}"
#
#grid.reset!
#
#puts grid.flow_info
#puts grid.info
#
#plot_flows grid, :n => 10, :focus => :reached
#plot_edges added.flatten, :color => "green", :width => 3
#show_plot



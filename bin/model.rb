#!/usr/bin/env ruby
require 'optimist'
require_relative '../electric_avenue.rb'

opts = Optimist::options do
  banner <<-EOS
Model a predefined geographic region.
Plot the lines, loads, and sources.
Do congestion reduction.

Usage:
  model.rb [options]
where [options] are:
EOS

  opt :region, "Which region to model (--list to see them all)", :type => :string, :default => "NEW_ENGLAND"
  opt :list, "List the available regions to model", :type => :boolean, :default => false
  opt :intermediate, "Show intermediate graphics of flow calculation", :type => :boolean
  opt :reduce, "How many times should we try to reduce congestion", :type => :integer, :default => 1
end

if opts[:list]
  puts "Regions available for modeling:"

  REGIONS.each do |name, coords|
    puts
    puts "#{"#{name}:".ljust(15)} N: #{coords[:n]}"
    puts "\tW: #{coords[:w]}\tE: #{coords[:e]}"
    puts "\t\tS: #{coords[:s]}"
  end

  exit
end

# More numbers that are divinely inspired.
# Sometimes I close my eyes and just see where the keyboard takes me.
#
# But actually, these were derived from the 7/22/22 @ 19:07:02 fuel mix.
# Then I grouped them logically (since the categories don't *quite* fit)
# and multiplied them by 1.11 to account for potential transmission loss.
# I'll adjust these numbers as need be based on the transmission loss that
# #calculate_flows! interprets.
opts[:region] = opts[:region].upcase
grid = Grid.within REGIONS[opts[:region]], :fuel => {:fossil  => 0.70,
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

added = []

opts[:reduce].times do
  new_edges = grid.reduce_congestion
  
  # TODO Are certain edges more effective than others? How do we know?
  added << []
  new_edges.each do |src, tgt, edge, dist|
    if edge.length < 0.5
      added[-1] << edge
      edge.mark_nodes!
    end
  end
  
  puts "New edges: #{added[-1].size}"
  
  grid.reset!
  
  puts grid.flow_info
  puts grid.info
end

plot_flows grid, :n => 10, :focus => :reached
plot_edges added.flatten, :color => "green", :width => 3
show_plot



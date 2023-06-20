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
  opt :reduce, "How many times should we try to reduce congestion", :type => :integer, :default => 1
  opt :quiet, "Don't show the graphs", :type => :boolean
  opt :parallel, "How many cores to use", :type => :integer, :default => 4
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

$parallel = opts[:parallel] == 0 ? false : opts[:parallel]

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

ng = nil
time "Grid simplification" do
  ng = grid.simplify
end

time "Grid calculations" do
  puts "\t#{grid.inspect}"
  grid.calculate_flows!
  
  puts grid.info
  puts grid.flow_info

  plot_flows grid, :n => 10
  plot_points grid.loads, :color => "cyan"
  show_plot
end

time "New grid calculations" do
  puts "\t#{ng.inspect}"

  ng.calculate_flows!

  plot_flows ng, :n => 10
  plot_points ng.loads, :color => "cyan"
  show_plot
  
  puts ng.info
  puts ng.flow_info
end

#plot_flows grid, :n => 10
#show_plot unless opts[:quiet]

added = []

time "Reducing congestion", :run => false do
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
end

time "Resiliency metrics" do
  puts "\tDrakos: #{ng.graph.j 0.4}"
end

plot_flows grid, :n => 10
plot_edges added.flatten, :color => "green", :width => 3
show_plot unless opts[:quiet]



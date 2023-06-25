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
  opt :quiet, "Don't show the graphs", :type => :boolean
  opt :parallel, "How many cores to use", :type => :integer, :default => 4
  opt :edges, "Max number of edges to build", :type => :integer, :default => 4
  opt :percentiles, "Which percentiles to pull from (low..high)", :type => :string, :default => "5..8"
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

$parallel = opts[:parallel] <= 1 ? false : opts[:parallel]
opts[:percentiles] = Range.new(*opts[:percentiles].split("..").map(&:to_i))

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
  show_plot unless opts[:quiet]
end

time "New grid calculations" do
  puts "\t#{ng.inspect}"
  ng.calculate_flows!
  
  puts ng.info
  puts ng.flow_info

  plot_flows ng, :n => 10
  plot_points ng.loads, :color => "cyan"
  show_plot unless opts[:quiet]
end

#plot_flows grid, :n => 10
#show_plot unless opts[:quiet]

added = []

grid = ng
time "Reduce congestion" do

  puts "\tPercentiles: #{opts[:percentiles]}"
  new_edges = grid.reduce_congestion opts[:percentiles]

  # Hard ceiling on the edge length
  candidates = new_edges.map {|_, _, e, _| e.length < 0.5 ? e : nil }.compact

  # potentially thousands of trials to run
  # We're only interested in building up to 4 edges here, since we're trying
  # to show bang for buck
  trials = (1..opts[:edges]).map {|i| candidates.combination(i).to_a }.flatten(1)

  puts "\tMax # of edges to build: #{opts[:edges]}"
  puts "\t#{candidates.size} candidates, #{trials.size} trials"

  # Test out each combination.
  # Detaching the edges in another process is unnecessary since the grid object
  # is copied (and thus the main processes's grid is unaffected), but the code is
  # included because it's cheap and is required for single-threaded ops
  results = trials.parallel_map do |cands|
    cands.each {|e, _, _| e.attach! }
    grid.reset!
    cands.each {|e, _, _| e.detach! }

    grid.transmission_loss[1]
  end
  results = trials.zip results

  # minimize tx loss, minimize total edge length
  ranked = results.sort_by do |cs, l|
    l ** 1.35 + l * cs.sum(&:length)
  end

  puts "\tTop 10 trials:"
  ranked[0..10].map do |cs, l|
    puts "\t\t# of Edges: #{cs.size}, " +
         "Length: #{cs.sum(&:length).round(2)}, " +
         "Tx loss: #{l.round(2)}%"
  end

  added = ranked[0][0]
  added.each {|e| e.attach! }

  grid.reset!

  puts grid.flow_info
  puts grid.info

  puts "\tQualifying edges: #{candidates.size}"
  puts "\tNew edges: #{added.size}"
  puts "\tTotal length: #{added.sum(&:length).round 2}"

  plot_flows grid, :n => 10
  plot_edges added, :color => "green", :width => 3
  show_plot unless opts[:quiet]
end

time "Resiliency metrics" do
  #profile do
    puts "\tDrakos: #{ng.resiliency :drakos,  0.4}"
  #end
end

# 60 sec to run
# 18 sec to calculate paths
# 42 sec to calculate sigmas
time "Weakest nodes" do

  # creating this value, which is already established from previous drakos runs
  grid.graph.paths

  sigmas = grid.graph.nodes.parallel_map do |v|
    grid.graph.sigma v, 0.4
  end

  pairs = grid.graph.nodes.zip(sigmas).sort_by {|v, s| s }

  require 'pry'
  binding.pry
end


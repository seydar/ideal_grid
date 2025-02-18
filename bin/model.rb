#!/usr/bin/env ruby --yjit -W0
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

grid = nil
ng = nil
time "Loading data", :run => false do

  if File.exists? "grid.bin"
    puts "\tFound cached version"
    grid = Marshal.load File.read("grid.bin")
  else

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
  end
end

time "Grid simplification" do

  if File.exist? "ng.bin"
    puts "\tFound cached version"
    ng = Marshal.load File.read("ng.bin")
  else
    ng = grid.simplify
  end
end

time "Grid calculations", :run => false do
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

  plot_flows ng.restrict(CT), :n => 10
  show_plot unless opts[:quiet]
end

#plot_flows grid, :n => 10
#show_plot unless opts[:quiet]

added = []

old  = grid
grid = ng
time "Reduce congestion" do

  puts "\tPercentiles: #{opts[:percentiles]}"
  new_edges = grid.reduce_congestion opts[:percentiles], :distance => 0.75

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

  added.each {|e| p [e, grid.flows[e]] }

  plot_flows grid.restrict(CT), :n => 3
  plot_edges added, :color => "green", :width => 3
  show_plot

  require 'pry'
  binding.pry

  plot_flows grid, :n => 10
  plot_edges added, :color => "green", :width => 3
  show_plot unless opts[:quiet]
end

time "Resiliency metrics", :run => false do
  #profile do
    puts "\tDrakos: #{ng.resiliency :drakos,  0.4}"
  #end
end

time "Strengthen nodes", :run => false do

  #grid.graph.paths

  #sigmas = grid.graph.nodes.parallel_map do |v|
  #  grid.graph.sigma v, 0.4
  #end

  #pairs = grid.graph.nodes.zip(sigmas).sort_by {|v, s| s }

  # Let's discuss the plan.
  # The plan is to make the most heavily relied-upon nodes less relied-upon.
  #
  # Interesting: while the most traffic node has 11 edges, some of the top
  # contenders only have 3 edges. There might be something in here that ties
  # to congestion reduction.

  # Take a high-sigma node.
  # Expand maybe ~3 steps around it (depends whether we're using the original
  #   or the simplified)
  # Remove the high-sigma node. Is it still singularly connected?
  # If so, move on to the next node.
  # If not, suggest edges that connect all pairs of the CG subgraphs
  #
  # or
  #
  # Take a high-sigma node
  # Gather all the paths that run through it
  # Look at which nodes will come up the most
  # And link them

  #high_sigma = pairs.reverse[0][0]
  # Cheating during this testing period
  high_sigma = grid.nodes.find {|n| n.id == 2988 }

  groups = grid.all_paths
  groups.each do |gen, demands|
    groups[gen] = demands.filter do |n, l, path|
      path & high_sigma.edges != []
    end
  end

  paths = groups.values.flatten(1).map do |_, _, path|
    path.map {|e| e.nodes }.flatten.uniq
  end

  nodes = paths.flatten
               .group_by {|n| n }
               .map {|k, vs| [k, vs.size] }
               .sort_by {|_, sz| sz }
               .reverse

  # Ugh, this is a combination of checking _ALL_ high sigma nodes and
  # ALL paths that cross them

  peak = nodes[0..50].map(&:first)
  popularity = paths.map {|p| [p, (p & peak).size] }.sort_by {|_, z| z }
  p popularity.count {|polku, _| polku.size >= 20 }

  require 'pry'
  binding.pry

  new_es = popularity.map do |polku, _|
    next if polku.size < 20

    pivot = polku.index high_sigma

    steps = (polku.size / 6.0).to_i

    floor = [pivot - 2 * steps, 0].max
    ceil  = [pivot + 2 * steps, polku.size - 1].min
    start, fin = polku[floor], polku[ceil]

    next unless start && fin

    src = ConnectedGraph.new([start]).expand :steps => 1
    dst = ConnectedGraph.new([fin]).expand :steps => 1

    e, _, _ = grid.connect_graphs_along_line(src, dst, :distance => 0.25)
    e
  end.compact

  new_es = new_es.uniq {|e| e.nodes }

  puts "Edges based on Node ##{high_sigma.id}: #{new_es.size}"
  new_es.each {|e| e.attach! }
  grid.reset!

  ranks  = new_es.map {|e| [e, grid.flows[e] / e.length] }
                 .sort_by {|_, f| f }

  new_es.each(&:detach!)
  new_es = ranks.map(&:first).filter {|e| e.length < 0.5 }
  new_es.each(&:attach!)

  puts "Qualifying edges: #{new_es.size}"

  grid.reset!
  puts grid.flow_info
  puts grid.info

  plot_flows grid
  plot_edges new_es, :color => "green"
  show_plot

  require 'pry'
  binding.pry
end


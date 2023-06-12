#!/usr/bin/env ruby
require 'csv'
require 'optimist'
require_relative "../electric_avenue.rb"

opts = Optimist::options do
  banner <<-EOS
Pretend a minimal electric grid is a minimum spanning tree across a bunch of nodes.
Now cluster them to determine where to put your generators.
Now add in extra edges to add resiliency.
Now calculate the capacity of each of the lines.

Usage:
  match_nodes.rb [options]
where [options] are:

EOS

  opt :region, "Which region to model (--list to see them all)", :type => :string, :default => "NEW_ENGLAND"
  opt :list, "List the available regions to model", :type => :boolean, :default => false
  opt :loads, "Match the loads from a CSV file to the structural nodes", :type => :string
  opt :gens, "Match the generators from a CSV file to the structural nodes"
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

# Need this so we can get the structural nodes
grid = Grid.within REGIONS[opts[:region].upcase]

if opts[:loads]
  # go from 1149 loads to 718
  # then down to 615 points after filtering for size
  #weights = CSV.parse File.read("data/isone/july-22/weights.txt")
  weights = CSV.parse File.read(opts[:loads])
  targets = weights.map {|n, mw| Load[:name => n] }.compact
  targets.zip(weights).each {|t, (n, mw)| t.max_peak_load = mw.to_f }
elsif opts[:gens]
  targets = Source.within REGIONS[opts[:region].upcase]
end

puts "Starting with #{targets.size} targets"
puts "Calculating distances between #{grid.nodes.size} nodes..."

# try to map the loads that we have to the nodes we have in the graph
pairs = targets.map {|l| [l, grid.graph.nodes.min_by {|n| l.point.euclidean_distance n }] }
pairs = pairs.map {|l, n| [l, n, l.point.euclidean_distance(n)] }

# This distance was determined empirically... AKA I pulled it out of my ass with some light graphing
pairs = pairs.filter {|_, _, d| d < 1e-3 }
es = pairs.map {|l, n, _| Edge.new l.point, n, :id => rand }

puts "After filtering: #{pairs.size}"

plot_grid grid
plot_points(pairs.map {|t, n, d| n.point }, :color => "blue")
plot_edges es, :color => "red"

leftover = targets - pairs.map {|t, n, d| t }
plot_points leftover.map(&:point), :color => "green"

show_plot

# Now take each pair and make it so that the load refers to the node
pairs.each do |l, n, d|
  l.point = n.point
  l.save
end

puts "#{pairs.size} points relocated"

require 'pry'
binding.pry


require_relative "../lib/db.rb"

# New England
NEW_ENGLAND = {:n =>  47.45, :s =>  40.94,
               :e => -66.85, :w => -73.45}

# Take all the loads and sources and build an edge that connects them to the
# nearest point from a line.

def nearest_point(set, target)
  set.map {|pt| [pt, pt.euclidean_distance(target)] }.min_by {|v| v[1] }
end

# TODO This doesn't take advantage of any lines we build during this process.
# Similar to the current transmission line upgrade process for renewable
# energy, it only looks at one thing at a time.
def connect(infra, pts)
  inserts = pts.map do |ld|
    pt = ld.point
    connection, dist = nearest_point infra, pt
    {:left_id  => connection.id,
     :right_id => pt.id,
     :length   => dist}
  end

  DB[:lines].multi_insert inserts
  inserts
end

def disconnected(edges, items)
  puts "#{items.size} total points"
  items.filter {|item| not edges.include? item.point }
end

# How identify a line?
# If it's got an edge, it's part of the infrastructure. Even in the future,
# I'm willing to connect loads to other nearby nodes instead of each of them
# having their own separate connection to the infrastructure (that'd be
# ridiculous)
lines = Line.eager(:left, :right).all
infra = lines.map {|l| [l.left, l.right] }.flatten

discon_ls = disconnected infra, Load.within(NEW_ENGLAND)
discon_ss = disconnected infra, Source.within(NEW_ENGLAND)

puts "#{discon_ls.size} disconnected loads"
puts "#{discon_ss.size} disconnected sources"

load_es = connect infra, discon_ls
src_es  = connect infra, discon_ss

puts "#{load_es.size + src_es.size} new edges created"
puts "\t#{load_es.size} for loads"
puts "\t#{src_es.size} for sources"

require 'pry'
binding.pry


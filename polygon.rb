require "overpass_api_ruby"
require 'json'
require 'proj'

require_relative 'lib/graph/edge.rb'
require_relative 'lib/graph/node.rb'
require_relative 'lib/plotting.rb'
require_relative 'lib/unionf.rb'

class Polygon
  attr_accessor :points

  def initialize(pts)
    @points = pts
  end

  def inspect
    "#<Polygon: #{points.size} points>"
  end

  def smooth(epsilon=2e-4, preserve=[])
    Polygon.new r_d_p(points, epsilon, preserve)
  end

  # Ramer-Douglas-Peucker algorithm
  # Wrote this once upon a time in Python back in the Navy. Beautiful algorithm
  # to have to your back pocket.
  def r_d_p(pts, epsilon=2e-4, preserve=[])
    return pts if pts.size <= 2

    max = 0
    idx = -1

    # No need to check the first and last points
    # Kinda wish I could make this shorter though
    pts[0..-2].each.with_index do |pt, i|
      # Don't test the first one
      # but we want i to start at 1 for when it matters
      # and I think this keeps the rest of the code clear
      next if i == 0

      if preserve.include? pt
        idx = i
        max = epsilon + 1 # arbitrary, just needs to be greater than epsilon
        break
      end

      dist = distance pt, pts[0], pts[-1]
      if dist > max
        max = dist
        idx = i
      end
    end

    if max > epsilon
      # Combine the two halves and strip the duplicated point
      # Ruby lets me make this one-liner almost too golfy
      #
      # Pass on the nodes we'd like to preserve and ensure that we NEVER remove
      r_d_p(pts[0..idx], epsilon, preserve) +
        r_d_p(pts[idx..-1], epsilon, preserve)[1..-1]
    else
      [pts[0], pts[-1]]
    end
  end

  # perpendicular distance from `p0` to the ray that passes
  # through `p1` and `p2`
  def distance(p0, p1, p2)
    numerator   = (((p2.x - p1.x) * (p1.y - p0.y)) -
                   ((p1.x - p0.x) * (p2.y - p1.y))).abs
    denominator = Math.sqrt((p2.x - p1.x) ** 2 + (p2.y - p1.y) ** 2)

    numerator / denominator
  end
end

def download_overpass
  query = "way['power'='line'];(._;>;);out body;"
  
  options = {:bbox => {:n =>  45.01, :s =>  42.71,
                       :e => -71.01, :w => -73.25}}
  #options = {:bbox => {:n =>  45.3154, :s =>  44.6424,
  #                     :e => -71.9248, :w => -72.627}}
  
  overpass = OverpassAPI::QL.new options
  response = overpass.query query

  lines = response[:elements].filter {|e| e[:type] == "way" }
  nodes = response[:elements].filter {|e| e[:type] == "node" }.map do |n|
    [n[:id], Node.new(n[:lon], n[:lat], :id => n[:id])]
  end.to_h
  
  $nodes = nodes.values
  $nodes.each {|n| n.load = 0 }
  
  lines.each do |line|
    line[:nodes]   = line[:nodes].map {|id| nodes[id] }
  end

  lines
end

def within(box, pt)
  pt.y < box[:n] &&
    pt.y > box[:s] &&
    pt.x < box[:e] &&
    pt.x > box[:w]
end

def read_geojson(path, box=nil)
  dedup = {}
  json  = JSON.load File.read(path)
  lines = json["features"]

  lines.each do |line|
    line[:nodes] = line['geometry']["coordinates"].map do |coord|
      dedup[coord] ||= Node.new(coord[0], coord[1], :id => dedup.size)
      dedup[coord].load = 0
      dedup[coord]
    end
  end

  if box
    lines.each do |line|
      line[:nodes] = line[:nodes].filter {|n| within box, n }
    end

    lines = lines.filter {|l| not l[:nodes].empty? }
  end

  $nodes = lines.map {|l| l[:nodes] }.flatten

  lines.each do |line|
    line[:polygon] = Polygon.new line[:nodes]
    line[:smooth] = line[:polygon].smooth
    line[:color] = COLORS.sample :random => PRNG
  end
end

def read_nodes(path, box)
  json = JSON.load File.read(path)
  points = json['f'].map {|f| f['g']['c'] }
  
  # Points are in some stupid format
  crs   = Proj::PjObject.new json['proj']
  trans = Proj::Transformation.new crs, 'epsg:4326'
  points = points.map do |x, y|
    from = Proj::Coordinate.new :x => x, :y => y
    to   = trans.forward from
    [to.x, to.y]
  end
end

def simplify(lines)
  # Track the nodes that are joints between lines
  # so that we can pass those in to the polygon simplification algorithm
  # to preserve those nodes
  #
  # R-D-P algorithm only works on a line, which means that each node can only
  #
  # "can only" what? I seem to have stopped in the middle of a sentence.
  # 
  # We can combine all of the points in the polygons and look at which
  # points are duplicated: THOSE are the ones we need to preserve
  full  = lines.map {|l| l[:nodes] }.flatten
  singles  = Set.new # This will make the `include?` call faster
  preserve = []
  full.each.with_index do |n, i|
    if singles.include? n.to_a
      preserve << n
    else
      singles << n.to_a
    end
  end
  
  
  lines.each do |line|
    line[:smooth] = line[:polygon].smooth 2e-4, preserve
  end
end

def super_simplify(lines)
  # Ugh have to recalculate this
  full  = lines.map {|l| l[:nodes] }.flatten
  singles  = Set.new # This will make the `include?` call faster
  preserve = Set.new
  full.each.with_index do |n, i|
    if singles.include? n.to_a
      preserve << n.to_a
    else
      singles << n.to_a
    end
  end

  # Need to add edge length into this somehow
  lines.each do |line|
    line[:save] = line[:nodes].filter.with_index do |pt, i|
      # first, last, or a junction node
      i == 0 or
        i == line[:nodes].size - 1 or
        preserve.include? pt.to_a
    end

    line[:super] = Polygon.new line[:save]
  end
end

def build_edges(poly)
  poly.points.each_cons(2).map.with_index do |(left, right), i|
    e = Edge.new left, right, :id => PRNG.rand # deal with the length later
    e.mark_nodes!
    e
  end
end

def show_poly(lines, poly)
  # Mark all the points on the smoothed lines
  # This should also take care of lines that use the same nodes
  lines.each {|l| l[:edges] = build_edges(l[poly]) }

  # Make connected lines have the same color
  # (instead of actually joining the polygons, we've merely joined them
  # in the U-F)
  lines.each {|l| l[:raw] = l[poly].points }
  
  uf = UnionF.new lines
  (0..lines.size - 1).each do |i|
    (i..lines.size - 1).each do |j|
      if lines[i][:raw] & lines[j][:raw] != []
        #uf.union lines[i], lines[j]
      end
    end
  end

  lines.each do |line|
    plot_edges line[:edges]
  end
  
  uf.disjoint_sets.each do |set|
    color = set[0][:color]
    set.each do |line|
      plot_points line[poly].points, :color => color
    end
  end

  puts "Plotting: #{poly}"
  show_plot

  uf
end

# Group all of the points by whether they're connected or not
def group_by_connected(points)
  uf = UnionF.new points

  (0..points.size - 1).each do |i|
    (i..points.size - 1).each do |j|
      if points[i].edge? points[j]
        uf.union points[i], points[j]
      end
    end
  end

  uf
end

# https://stackoverflow.com/a/19375910
#
# This will destroy object IDs, but that's to be expected, since new
# points are being made
#
# Problems with this algorithm:
#   a new point could suddenly fall into the radius of a new point; won't be noticed
#     (this might be good, otherwise you could have a line of points get
#     merged into 1)
#   depends upon the order of the points in the input
#
# But since some points will have edges, we can't just scrap everything entirely.
# How do I transfer over the edges?
#
# Edges need to be built for the unjoined lines first
#
# Edges are good to go, but since points get replaced, you end up with a _LOT_
# of duplicate edges in the end product. Gotta reduce those somehow.
def join_points(points, dist=0)
  joined = [] # return a list of all points 
  taken  = Set.new

  # TODO This algorithm would be better if it tracked a moving centroid and
  # calculated the distance from there, because right now this algorithm is
  # "unstable": it depends upon the order of input points
  (0..points.size - 1).each do |i|
    next if taken.include? i

    # Having a duplicated variable here is important because it represents the
    # centroid. We want to separately measure the distance to points[i] though
    centroid = points[i].dup
    centroid.id += points.size # we NEED unique IDs
    centroid.edges.each {|e| e.replace points[i], centroid }
    centroid.sources << points[i]

    # We're going to average the nearby points at the end -- here's our tally
    count = 1
    taken << i

    (i + 1..points.size - 1).each do |j|
      # If the points are neighbors, average them together
      if points[i].euclidean_distance(points[j]) < dist &&
         !taken.include?(j)

        centroid.x += points[j].x
        centroid.y += points[j].y

        # Add the edges first and then replace points[j] everywhere
        centroid.edges += points[j].edges
        centroid.edges.each {|e| e.replace points[j], centroid }

        # debugging
        centroid.sources << points[j]

        count += 1
        taken << j
      end
    end

    centroid.x /= count.to_f
    centroid.y /= count.to_f

    joined << centroid
  end

  joined
end

# Ugh. This isn't clean, but it'll do for now. Eventually I need to clean
# this up and do something that's not a hack.
#
# TODO Why do I need the call to #uniq? An edge is getting duplicated at
# some point and I cannot for the life of me figure out where or why. Frankly,
# I just don't care anymore. This code is trying its best to not work, and I'm
# not going to let it get away with that.
#
# God dammit.
#
# I *also* need to get rid of edges that skip over other nodes. This is a weird
# edge case that is apparently not too uncommon. Two lines are overlaid, but
# their points are not *quite* so. So when they get joined, you end up having a
# point that has too many edges and skips over another, more proximate point.
def deduplicate_edges(points)
  es = points.map {|p| p.edges }.flatten

  # Only unique edges
  es = es.uniq {|e| e.nodes.sort_by {|n| n.id } }

  # No loopbacks
  es = es.reject {|e| e.nodes[0] == e.nodes[1] }

  deduped = Set.new es

  # Restrict to only the approved edges
  points.each do |pt|
    pt.edges = pt.edges.filter {|e| deduped.include? e }.uniq
  end

  # Get rid of edges that skip over other nodes
  # We can plan for it and say that any node that is within a certain distance
  # of a line should be merged into the ege.
  
end


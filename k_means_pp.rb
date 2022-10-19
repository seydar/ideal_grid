# Modified from https://github.com/ollie/k_means_pp
require_relative 'k_means_pp/point'
require_relative 'k_means_pp/cluster'

# Cluster data with the k-means++, k-means and Lloyd algorithm.
class KMeansPP
  PARALLELIZE_CLUSTER = proc {|pts| $parallel && pts.size > 100 }

  def self.graph
    @@graph
  end

  def self.graph=(val)
    @@graph = val
  end

  # Source data set of points.
  #
  # @return [Array<Point>]
  attr_accessor :points

  # Centroid points
  #
  # @return [Array<Centroid>]
  attr_accessor :centroids

  # Take an array of things and group them into K clusters.
  #
  # If no block was given, an array of arrays (of two numbers) is expected.
  # At the end an array of +Cluster+s is returned, each wrapping
  # an array or arrays (of two numbers).
  #
  # If a block was given, the +points+ is likely an array of other things
  # like hashes or objects. The block is expected to return an array of two
  # numbers. At the end an array of +Cluster+s is returned, each wrapping
  # an array or original objects.
  #
  # @param points         [Array]  Source data set of points.
  # @param clusters_count [Fixnum] Number of clusters ("k").
  # @yieldreturn [Array<Numeric>]
  #
  # @return [Array<Cluster>]
  def self.clusters(points, clusters_count, &block)
    instance = new(points, clusters_count, &block)
    instance.group_points
    instance.centroids.map do |centroid|
      cluster_for_centroid(centroid, instance.points, block)
    end
  end

  # Computed points are a flat structure so this nests each point
  # in an array.
  #
  # @param centroid [Centroid] Centroid of the cluster.
  #
  # @return [Cluster]
  def self.cluster_for_centroid(centroid, points, block)
    cluster_points = points.select { |p| p.group == centroid }

    if block
      cluster_points.map!(&:original)
    else
      cluster_points.map! { |p| [p.x, p.y] }
    end

    Cluster.new(centroid, cluster_points)
  end

  # Find nearest centroid for a given point in given centroids.
  #
  # @param point     [Point]           Measure distance of this point
  # @param centroids [Array<Centroid>] to those cluster centers
  #
  # @return [Centroid]
  def self.find_nearest_centroid(point, centroids)
    find_nearest_centroid_and_distance(point, centroids)[0]
  end

  # Find distance to the nearest centroid for a given point in given centroids.
  #
  # @param point     [Point]           Measure distance of this point
  # @param centroids [Array<Centroid>] to those cluster centers
  #
  # @return [Float]
  def self.find_nearest_centroid_distance(point, centroids)
    find_nearest_centroid_and_distance(point, centroids)[1]
  end

  # Find the nearest centroid in given centroids.
  #
  # @param point     [Point]           Measure distance of this point
  # @param centroids [Array<Centroid>] to those cluster centers
  #
  # @return [Array]
  def self.find_nearest_centroid_and_distance(point, centroids)
    # Assume the current centroid is the closest.
    nearest_centroid = point.group
    nearest_distance = Float::INFINITY

    centroids.each do |centroid|
      #distance = centroid.manhattan_distance(point)
      distance = graph.manhattan_distance from: centroid.original,
                                          to:   point.original

      next if distance >= nearest_distance

      nearest_distance = distance
      nearest_centroid = centroid
    end

    [nearest_centroid, nearest_distance]
  end

  # Take an array of things and group them into K clusters.
  #
  # If no block was given, an array of arrays (of two numbers) is expected.
  # Internally we map them with +Point+ objects.
  #
  # If a block was given, the +points+ is likely an array of other things
  # like hashes or objects. In this case we will keep the original object
  # in a property and once we are done, we will swap those objects.
  # The block is expected to retun an array of two numbers.
  #
  # @param points         [Array]  Source data set of points.
  # @param clusters_count [Fixnum] Number of clusters ("k").
  # @yieldreturn [Array<Numeric>]
  def initialize(points, clusters_count)
    # Do not mutate original structure
    points = points.dup

    if block_given?
      points.map! do |point_obj|
        point_ary      = yield(point_obj)
        point          = Point.new(point_ary[0], point_ary[1])
        point.original = point_obj
        point
      end
    else
      points.map! do |point_ary|
        Point.new(point_ary[0], point_ary[1])
      end
    end

    self.points    = points
    self.centroids = Array.new(clusters_count)
  end

  # Group points into clusters.
  def group_points
    define_initial_clusters
    fine_tune_clusters
  end

  protected

  # K-means++ algorithm.
  #
  # Find initial centroids and assign points to their nearest centroid,
  # forming cells.
  def define_initial_clusters
    # Randomly choose a point as the first centroid.
    centroids[0] = Centroid.new points.sample(:random => PRNG), 0

    # Initialize an array of distances of every point.
    distances = points.size.times.map { 0.0 }

    centroids.each_with_index do |_, centroid_i|
      # Skip the first centroid as it's already picked but keep the index
      next if centroid_i == 0

      # Sum points' distances to their nearest centroid
      distances_sum = 0.0

      points.each_with_index do |point, point_i|
        distance = self.class.find_nearest_centroid_distance(
          point,
          centroids[0...centroid_i]
        )

        distances[point_i] = distance
        distances_sum += distance
      end

      # Randomly cut it.
      distances_sum *= PRNG.rand

      # Keep subtracting those distances until we hit a zero (or lower)
      # in which case we found a new centroid.
      distances.each_with_index do |distance, point_i|
        distances_sum -= distance
        next if distances_sum > 0
        centroids[centroid_i] = Centroid.new points[point_i], centroid_i
        break
      end

    end

    # Assign each point its nearest centroid.
    if PARALLELIZE_CLUSTER[points]
      # Parallel
      cs = points.parallel_map do |point|
        self.class.find_nearest_centroid point, centroids
      end

      # Convert from the mashalled Centroids in `cs` to the actual ones 
      # we want.
      #self.centroids = centroids.map do |centroid|
      #  cs.find {|c| c.id == centroid.id }
      #end
      
      cs = cs.map do |centroid|
        centroids.find {|c| c.id == centroid.id }
      end

      points.zip(cs).each do |point, centroid|
        point.group = centroid
      end

    else
      points.each do |point|
        point.group = self.class.find_nearest_centroid(point, centroids)
      end
    end
  end

  # This is Lloyd's algorithm
  # https://en.wikipedia.org/wiki/Lloyd%27s_algorithm
  #
  # At this point we have our points already assigned into cells.
  #
  # 1. We calculate a new center for each cell.
  # 2. For each point find its nearest center and re-assign it if it changed.
  # 3. Repeat until a threshold has been reached.
  def fine_tune_clusters
    # When a number of changed points reaches this number, we are done.
    changed_threshold = points.size >> 10

    history = [-3, -2, -1]

    loop do
      calculate_new_centroids

      changed = reassign_points
      history << changed
      puts "\t#{changed} changed"

      centroids.map do |centroid|
        self.class.cluster_for_centroid(centroid, points, true)
      end

      # Stop when 99.9% of points are good
      break if changed <= changed_threshold

      # FIXME still got the bug where it fails to converge and gets stuck
      # swapping two points back and forth
      # why do i suck
      if history.size > 4 && history[-4..-3] == history[-2..-1]
        puts "\t***FAILED TO CONVERGE***"
        break
      end
    end
  end

  # Get point pair that has longest path
  # Select median node
  def calculate_new_centroids
    centroids.each do |centroid|
      cluster = self.class.cluster_for_centroid(centroid, points, true)

      graph = ConnectedGraph.new cluster.points
      path  = graph.longest_path

      # Path will be empty if there is only one point in the cluster
      median = path.size == 0 ? cluster.points[0] : path.median

      begin
        centroid.set median
      rescue => e
        require 'pry'
        binding.pry
      end
    end
  end

  # Loop through all the points and find their nearest centroid.
  # If it's a different one than current, change it ande take a note.
  #
  # @return [Fixnum] Number of changed points.
  def reassign_points
    changed = 0

    if PARALLELIZE_CLUSTER[points]
      # Parallel
      cs = points.parallel_map do |point|
        self.class.find_nearest_centroid point, centroids
      end

      # Convert from the mashalled Centroids in `cs` to the actual ones 
      # we want.
      cs = cs.map do |centroid|
        centroids.find {|c| c.id == centroid.id }
      end

      points.zip(cs).each do |point, centroid|
        next if centroid == point.group
        changed += 1
        point.group = centroid
      end

      changed
    else
      # Sequential
      points.each do |point|
        centroid = self.class.find_nearest_centroid(point, centroids)
        next if centroid == point.group
        changed += 1
        point.group = centroid
      end

      changed
    end
  end
end

module Siting
  # Included in `ConnectedGraph`

  def site_median
    longest_path.median
  end

  # This isn't getting everyone in the way I'd like it to.
  #
  # Issue: because a generator is supplying power to another cluster
  # before fullying supplying its own because it is place in the median
  # of the longest path, but that doesn't mean another cluster isn't closer
  #
  # Usually, we'd place the generator at the middle node on the longest
  # path in a cluster. BUT, since nodes in clusters are unevenly
  # distributed, that means that other nodes in other clusters could be
  # closer than nodes within the cluster we're trying to service.
  #
  # So we need to place the generator at a distance that is *farther* away
  # from other clusters. The farthest node would work (step 1. find the
  # closest node to another cluster; step 2. find the farthest node away)
  #
  # Or better yet:
  #   1. Find all the nodes in a cluster that have edges leading outside
  #      the cluster.
  #   2. Find the longest paths from those nodes.
  #   3. Place the generator at the endpoint.
  #      3.a. This is simple if we have only one border node: place the
  #           generator at the endpoint farthest away.
  #      3.b. If we have 2 border nodes, find the longest path between the
  #           two endpoints, and place the generator at the median.
  #           (I'm thinking of the worst-case where the cluster is a
  #           straight line and the border nodes are on either end)
  #      3.c. If we have 3 border nodes... then we're... guaranteed to
  #           have some bleedover (as we are with 2 nodes, since the median
  #           node is possibly going to be biased towards one side)
  #      3.d. ... So just pick the two longest paths regardless and find
  #           the median between them.
  #
  # Caveat: This is measuring distance by transmission line length, not
  #         number of nodes along the way.
  #
  # Let's get to work!
  def site_on_premises
    # Steps 1 and 2
    farthest_nodes = border_nodes.map do |node|
      # The block here means that we're counting one unit of distance
      # per edge, i.e. we're counting the number of edges and not the
      # length of the edges (as would be the default)
      farthest_node_from(node) { 1 }
    end

    # Step 3
    if farthest_nodes.size == 1 # Step 3.a
      new_spot = farthest_nodes[0][0]
    else # Step 3.d
      pen, ult = farthest_nodes.sort_by {|n, d| d }[-2..-1]
      if pen[0] == ult[0]
        new_spot = pen[0]
      else
        path = Path.build pen[0].path_to(ult[0])
        new_spot = path.median
      end
    end

    new_spot
  end

  # Okay, so for this one, we're going to be adding a new node to the global
  # body of nodes (as well as new edges).
  #
  # This means we're going to spoil the cache. Could be worse.
  #
  # Things to do:
  #   Combine separate connected graphs if there's nothing else in between them
  def site_new_location
    centroid_x = nodes.map {|n| n.x }.avg
    centroid_y = nodes.map {|n| n.y }.avg
    centroid = Node.new centroid_x, centroid_y

    nodes.sort_by {|n| n.euclidean_distance centroid }[0..1]
    raise "broken"
  end
end


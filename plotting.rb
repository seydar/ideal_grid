$plot = Gnuplot::Plot.new
COLORS = ["#ffa3d7", "#bcffa3", "#ebffa3", "#ebffa3"]

def buffered_range(points, buffer=0.1)
  range = buffered_range_int points
  "[#{range[0]}:#{range[1]}]"
end

def buffered_range_int(points, buffer=0.1)
  max = points.max
  min = points.min
  range = max - min
  buffer = range * buffer
  [min - buffer, max + buffer]
end

def read_buffered_range(range)
  range ||= [nil, nil, "[0:0]"]
  range[2][1..-2].split(":").map {|p| p.to_f }
end

def cplot(points, color: nil)
  plot [KMeansPP::Cluster.new(points.first, points)], :color => color
end

def pplot(path)
  cplot path.nodes
end

def gplot(graph)
  plot [KMeansPP::Cluster.new(graph.longest_path.median, graph.nodes)]
end

def update_ranges(nodes)
  xr = buffered_range_int(nodes.map {|p| p.x }, 0.2)
  yr = buffered_range_int(nodes.map {|p| p.y }, 0.2)

  xprev = read_buffered_range($plot.settings.find {|e| e[1] == "xrange" })
  yprev = read_buffered_range($plot.settings.find {|e| e[1] == "yrange" })
  $plot.xrange "[#{[xprev[0], xr[0]].min}:#{[xprev[1], xr[1]].max}]"
  $plot.yrange "[#{[yprev[0], yr[0]].min}:#{[yprev[1], yr[1]].max}]"
end

def plot_edges(edges, color: nil)
  $plot.data += edges.map do |edge|
    xs = edge.nodes.map(&:x)
    ys = edge.nodes.map(&:y)
  
    Gnuplot::DataSet.new([xs, ys]) do |ds|
      ds.with = 'lines'
      ds.notitle
      ds.linecolor = "-1"
    end
  end
end

def plot_points(nodes, color: nil, point_type: 6)
  return if nodes.empty?

  xs = nodes.map {|p| p.x }
  ys = nodes.map {|p| p.y }
  
  ds = Gnuplot::DataSet.new([xs, ys]) do |ds|
    ds.with = "points pointtype #{point_type}"
    ds.notitle
    ds.linecolor = "rgb \"#{color || COLORS.sample}\""
  end
  $plot.data << ds
end

def plot_point(point, color: nil, point_type: 6)
  plot_points [point], :color => color
end

def plot_graph(graph, color: nil, point_type: 6)
  update_ranges graph.nodes

  edges = graph.nodes.map {|n| n.edges }.flatten

  plot_edges edges
  plot_points graph.nodes, :color => 'red'
end

def plot_grid(grid)
  plot_graph grid

  grid.generators.each do |gen|
    plot_points gen.reach.nodes, :color => "#6e6e6e"
    plot_point gen.node, :color => "red"
  end
end

def plot_clusters(clusters, color: nil)
  nodes = clusters.map {|c| c.points }.flatten
  edges = nodes.map {|n| n.edges }.flatten

  # update x and y axes
  update_ranges nodes
  
  plot_edges edges

  varet = [*(color || COLORS)]
  
  # Plotting cluster constituents
  clusters.zip(varet).each do |cluster, color|
    plot_points cluster.points, :color => color, :point_type => 7
  end
  
  # Plotting cluster centroids
  clusters.each do |cluster|
    plot_point cluster.centroid, :color => "orange", :point_type => 6
  end
end

def show_plot
  $plot, plot = Gnuplot::Plot.new, $plot

  Gnuplot.open do |gp|
    gp << plot.to_gplot
    gp << plot.store_datasets
  end

  update_ranges $nodes
end


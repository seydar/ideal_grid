$plot = Gnuplot::Plot.new

def buffered_range(points, buffer=0.1)
  range = buffered_range_int
  "[#{range[0]}:#{range[1]}]"
end

def buffered_range_int(points, buffer=0.1)
  max = points.max
  min = points.min
  range = max - min
  buffer = range * buffer
  [min - buffer, max + buffer]
end

def cplot(points)
  plot [KMeansPP::Cluster.new(points.first, points)]
end

def pplot(path)
  cplot path.nodes
end

def gplot(graph)
  plot [KMeansPP::Cluster.new(graph.longest_path.median, graph.nodes)]
end

def plot_points(nodes, color: nil)

end

def plot_graph(graph, color: nil)
end

def plot(clusters)
  nodes = clusters.map {|c| c.points }.flatten
  edges = nodes.map {|n| n.edges }.flatten

  xr = buffered_range_int(nodes.map {|p| p.x }, 0.2)
  yr = buffered_range_int(nodes.map {|p| p.y }, 0.2)

  xprev = ($plot.settings.find {|e| e[1] == "xrange" } || [nil, nil, "[0:0]"])[2][1..-2].split(":").map {|p| p.to_f }
  yprev = ($plot.settings.find {|e| e[1] == "yrange" } || [nil, nil, "[0:0]"])[2][1..-2].split(":").map {|p| p.to_f }
  $plot.xrange "[#{[xprev[0], xr[0]].min}:#{[xprev[1], xr[1]].max}]"
  $plot.yrange "[#{[yprev[0], yr[0]].min}:#{[yprev[1], yr[1]].max}]"
  
  xs, ys = nodes.map {|p| p.x }, nodes.map {|p| p.y }
  $plot.data << Gnuplot::DataSet.new([xs, ys])
  
  $plot.data += edges.map do |edge|
    xs = edge.nodes.map(&:x)
    ys = edge.nodes.map(&:y)
  
    Gnuplot::DataSet.new([xs, ys]) do |ds|
      ds.with = 'lines'
      ds.notitle
      ds.linecolor = "-1"
    end
  end
  
  colors = clusters.zip(["red", "blue", "yellow", "magenta"]).to_h
  
  # Plotting cluster constituents
  $plot.data += clusters.map do |cluster|
    xs = cluster.points.map {|p| p.x }
    ys = cluster.points.map {|p| p.y }
  
    Gnuplot::DataSet.new([xs, ys]) do |ds|
      ds.with = 'points pointtype 6'
      ds.notitle
      ds.linecolor = "rgb \"#{colors[cluster]}\""
    end
  end
  
  # Plotting cluster centroids
  $plot.data += clusters.map do |cluster|
    xs = [cluster.centroid.x]
    ys = [cluster.centroid.y]
  
    Gnuplot::DataSet.new([xs, ys]) do |ds|
      ds.with = 'points pointtype 6 pointsize 3'
      ds.notitle
      ds.linecolor = 'rgb "orange"'
    end
  end
end

def show_plot
  $plot, plot = Gnuplot::Plot.new, $plot

  Gnuplot.open do |gp|
    gp << plot.to_gplot
    gp << plot.store_datasets
  end
end


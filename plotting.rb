def buffered_range(points, buffer=0.1)
  max = points.max
  min = points.min
  range = max - min
  buffer = range * buffer
  "[#{min - buffer}:#{max + buffer}]"
end

def cplot(points)
  plot [KMeansPP::Cluster.new(points.first, points)]
end

def plot(clusters)
  nodes = clusters.map {|c| c.points }.flatten
  edges = nodes.map {|n| n.edges }.flatten

  Gnuplot.open do |gp|
    Gnuplot::Plot.new gp do |plot|
  
      plot.xrange buffered_range(nodes.map {|p| p.x }, 0.2)
      plot.yrange buffered_range(nodes.map {|p| p.y }, 0.2)
  
      xs, ys = nodes.map {|p| p.x }, nodes.map {|p| p.y }
      plot.data << Gnuplot::DataSet.new([xs, ys])
  
      plot.data += edges.map do |edge|
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
      plot.data += clusters.map do |cluster|
        xs = cluster.points.map {|p| p.x }
        ys = cluster.points.map {|p| p.y }
  
        Gnuplot::DataSet.new([xs, ys]) do |ds|
          ds.with = 'points pointtype 6'
          ds.notitle
          ds.linecolor = "rgb \"#{colors[cluster]}\""
        end
      end
  
      # Plotting cluster centroids
      plot.data += clusters.map do |cluster|
        xs = [cluster.centroid.x]
        ys = [cluster.centroid.y]
  
        Gnuplot::DataSet.new([xs, ys]) do |ds|
          ds.with = 'points pointtype 6 pointsize 3'
          ds.notitle
          ds.linecolor = 'rgb "orange"'
        end
      end
  
    end
  end
end


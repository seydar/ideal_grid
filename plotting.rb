$plot = Gnuplot::Plot.new
#COLORS = ["green", "cyan", "purple", "blue", "#ffa3d7", "#bcffa3", "#ebffa3", "#ebffa3"]

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

def update_ranges(nodes)
  xr = buffered_range_int(nodes.map {|p| p.x }, 0.2)
  yr = buffered_range_int(nodes.map {|p| p.y }, 0.2)

  xprev = read_buffered_range($plot.settings.find {|e| e[1] == "xrange" })
  yprev = read_buffered_range($plot.settings.find {|e| e[1] == "yrange" })
  $plot.xrange "[#{[xprev[0], xr[0]].min}:#{[xprev[1], xr[1]].max}]"
  $plot.yrange "[#{[yprev[0], yr[0]].min}:#{[yprev[1], yr[1]].max}]"
end

def plot_edges(edges, color: "black", width: 1)
  $plot.data += edges.map do |edge|
    xs = edge.nodes.map(&:x)
    ys = edge.nodes.map(&:y)
  
    Gnuplot::DataSet.new([xs, ys]) do |ds|
      ds.with = 'lines'
      ds.notitle
      ds.linecolor = "rgb \"#{color}\""
      ds.linewidth = width
    end
  end

  nil
end

def plot_edge(edge, color: "black", width: 1)
  plot_edges [edge], :color => color, :width => width
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

  nil
end

def plot_point(point, color: nil, point_type: 6)
  plot_points [point], :color => color, :point_type => point_type
end

def plot_graph(graph, color: "blue", edge_color: "black", point_type: 6)
  update_ranges graph.nodes

  edges = graph.nodes.map {|n| n.edges }.flatten

  plot_edges edges, :color => edge_color
  plot_points graph.nodes, :color => color, :point_type => point_type
end

def plot_grid(grid, focus=:unreached)
  # Do we want to draw attention to the unreached or the reached?
  c1, c2 = "blue", "gray"
  c1, c2 = c2, c1 if focus == :reached

  plot_graph grid.graph, :color => c1
  plot_graph grid.reach, :color => c2

  grid.generators.each {|g| plot_generator g }
end

def plot_path(path, color: nil)
  plot_edges path.edges, :color => color
  plot_points path.nodes, :color => color
end

def plot_generator(gen, color: "red")
  plot_point gen.node, :color => color, :point_type => 7
end

def plot_cluster(cluster, gen)
  plot_graph cluster
  plot_generator gen
end

def plot_flows(grid, n: 10, focus: :unreached)
  flows = grid.flows
  max, min = flows.values.max || 0, flows.values.min || 0
  #max, min = ($nodes.size / 6).round(1), 1
  splits = n.times.map {|i| (max - min) * i / n.to_f + min }
  splits = [*splits, [flows.values.max || 0, max].max + 1]

  # low to high, because that's how splits is generated
  percentiles = splits.each_cons(2).map do |bottom, top|
    flows.filter {|e, f| f >= bottom && f < top }.map {|e, f| e }
  end

  plot_grid grid, focus

  colors = BLUES.reverse + REDS
  percentiles.each.with_index do |pc, i|
    plot_edges pc, :color => colors[(i * colors.size) / n], :width => (i * 3.0 / n)
  end

  # Plot the untread edges to see if there are any even breaks in the grid
  edges = grid.graph.nodes.map {|n| n.edges }.flatten.uniq
  untread = edges - grid.flows.keys
  plot_edges untread, :color => "cyan"
end

def show_plot
  $plot, plot = Gnuplot::Plot.new, $plot

  Gnuplot.open do |gp|
    gp << plot.to_gplot
    gp << plot.store_datasets
  end

  update_ranges $nodes
end

def save_plot(fname)
  $plot, plot = Gnuplot::Plot.new, $plot

  Gnuplot.open do |gp|
    plot.terminal 'pngcairo size 640,480'
    plot.output fname
    gp << plot.to_gplot
    gp << plot.store_datasets
  end

  update_ranges $nodes
end

# Monochromatic scale in red
# https://www.toptal.com/designers/colourcode/monochrome-color-builder
REDS = ["#1C0A0C",
        "#42171C",
        "#68232C",
        "#8F2F3B",
        "#B73B4A",
        "red"]

# Monochromatic scale in blue
# https://www.toptal.com/designers/colourcode/monochrome-color-builder
BLUES = ["#16173E",
         "#232465",
         "#2F318B",
         "#3B3DB3",
         "#5759C9",
         "blue"]

# Generated from https://mokole.com/palette.html
COLORS = ["#696969",
          "#556b2f",
          "#8b4513",
          "#006400",
          "#8b0000",
          "#808000",
          "#483d8b",
          "#3cb371",
          "#bc8f8f",
          "#008080",
          "#4682b4",
          "#000080",
          "#9acd32",
          "#32cd32",
          "#daa520",
          "#7f007f",
          "#b03060",
          "#ff0000",
          "#00ced1",
          "#ff8c00",
          "#ffff00",
          "#00ff00",
          "#8a2be2",
          "#dc143c",
          "#00bfff",
          "#f4a460",
          "#9370db",
          "#0000ff",
          "#f08080",
          "#adff2f",
          "#ff00ff",
          "#1e90ff",
          "#f0e68c",
          "#dda0dd",
          "#add8e6",
          "#ff1493",
          "#ee82ee",
          "#98fb98",
          "#7fffd4",
          "#ffdab9"]


require 'gnuplot'
$plot = Gnuplot::Plot.new

def resize_plot(x=750, y=600)
  $plot.terminal "qt size #{x},#{y}"
end

def buffered_range(points, buffer=0.1)
  range = buffered_range_int points, buffer
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
  #range ||= [nil, nil, "[0:0]"]
  return nil unless range
  range[2][1..-2].split(":").map {|p| p.to_f }
end

def update_ranges(nodes)
  xr = buffered_range_int(nodes.map {|p| p.x }, 0.05)
  yr = buffered_range_int(nodes.map {|p| p.y }, 0.05)

  xprev = read_buffered_range($plot.settings.find {|e| e[1] == "xrange" })
  yprev = read_buffered_range($plot.settings.find {|e| e[1] == "yrange" })

  xprev ||= xr
  yprev ||= yr

  $plot.xrange "[#{[xprev[0], xr[0]].min}:#{[xprev[1], xr[1]].max}]"
  $plot.yrange "[#{[yprev[0], yr[0]].min}:#{[yprev[1], yr[1]].max}]"
end

def plot_edges(edges, color: "black", width: 1, labels: [])
  return if edges.empty?

  $plot.data += edges.zip(labels).map do |edge, label|
    xs = edge.nodes.map(&:x)
    ys = edge.nodes.map(&:y)

    if label
      center = [xs.avg, ys.avg]
      $plot.arbitrary_lines << "set label \"#{label}\" at #{center.join(",")} offset 2"
    end
  
    Gnuplot::DataSet.new([xs, ys]) do |ds|
      ds.with = 'lines'
      ds.notitle
      ds.linecolor = "rgb \"#{color}\""
      ds.linewidth = width
    end
  end

  nil
end

def plot_edge(edge, color: "black", width: 1, label: nil)
  plot_edges [edge], :color => color, :width => width, :labels => [*label]
end

def plot_points(nodes, color: nil, point_type: 6, labels: [])
  return if nodes.empty?

  xs = nodes.map {|p| p.x }
  ys = nodes.map {|p| p.y }

  if labels && !labels.empty?
    nodes.zip(labels).each do |node, label|
      center = [node.x, node.y]
      $plot.arbitrary_lines << "set label \"#{label}\" at #{center.join(",")} offset 2"
    end
  end
  
  ds = Gnuplot::DataSet.new([xs, ys]) do |ds|
    ds.with = "points pointtype #{point_type}"
    ds.notitle
    ds.linecolor = "rgb \"#{color || COLORS.sample}\""
  end
  $plot.data << ds

  nil
end

def plot_point(point, color: nil, point_type: 6, label: nil)
  plot_points [point], :color => color, :point_type => point_type, :labels => [*label]
end

def plot_group(points, color: nil, point_type: 6)
  es = points.map(&:edges).flatten.uniq
  plot_edges es, :color => "black"
  plot_points points, :color => color, :point_type => point_type
end

def plot_graph(graph, color: "blue", edge_color: "black", point_type: 6)
  update_ranges graph.nodes

  edges = graph.nodes.map {|n| n.edges }.flatten

  plot_edges edges, :color => edge_color

  ns = graph.nodes.filter {|n| n.load == 0 }
  plot_points ns, :color => "gray", :point_type => 6

  ns = graph.nodes.filter {|n| n.load != 0 }
  plot_points ns, :color => color, :point_type => 6
end

def plot_grid(grid, restrict: nil)
  plot_graph grid.graph, :color => "gray"

  grid.generators.each {|g| plot_generator g }

  nil
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

def plot_flows(grid, n: 10, labels: false)
  flows = grid.flows
  max, min = flows.values.max || 0, flows.values.min || 0
  #max, min = ($nodes.size / 6).round(1), 1
  splits = n.times.map {|i| (max - min) * i / n.to_f + min }
  splits = [*splits, [flows.values.max || 0, max].max + 1]

  # low to high, because that's how splits is generated
  percentiles = splits.each_cons(2).map do |bottom, top|
    flows.filter {|e, f| f >= bottom && f < top }.map {|e, f| e }
  end

  plot_grid grid

  colors = BLUES.reverse + REDS
  percentiles.each.with_index do |pc, i|
    rhea = labels ? pc.map {|e| flows[e].round(2) } : []
    plot_edges pc, :color  => colors[((i + 1) * colors.size) / (n + 1)],
                   :width  => (i * 3.0 / n),
                   :labels => rhea
  end

  # Plot the untread edges to see if there are any even breaks in the grid
  edges = grid.graph.nodes.map {|n| n.edges }.flatten.uniq
  untread = edges - grid.flows.keys
  plot_edges untread, :color => "cyan"
end

def show_plot
  resize_plot
  $plot, plot = Gnuplot::Plot.new, $plot

  Gnuplot.open do |gp|
    gp << plot.to_gplot
    gp << plot.store_datasets
  end

  update_ranges $nodes unless $nodes.nil? || $nodes.empty?
  resize_plot
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
#REDS = ["#1C0A0C",
#        "#42171C",
#        "#68232C",
#        "#8F2F3B",
#        "#B73B4A",
#        "red"]

# Made by hand using ruby color-math
# HSL (360, 100, [25-50]) => hex
REDS = ["#800000",
        "#850000",
        "#8A0000",
        "#8F0000",
        "#940000",
        "#990000",
        "#9E0000",
        "#A30000",
        "#A80000",
        "#AD0000",
        "#B30000",
        "#B80000",
        "#BD0000",
        "#C20000",
        "#C70000",
        "#CC0000",
        "#D10000",
        "#D60000",
        "#DB0000",
        "#E00000",
        "#E60000",
        "#EB0000",
        "#F00000",
        "#F50000",
        "#FA0000",
        "#FF0000"]

# Monochromatic scale in blue
# https://www.toptal.com/designers/colourcode/monochrome-color-builder
#BLUES = ["#16173E",
#         "#232465",
#         "#2F318B",
#         "#3B3DB3",
#         "#5759C9",
#         "blue"]

# more math
# HSL(240, 100, [25-50])
BLUES = ["#000080",
         "#000085",
         "#00008A",
         "#00008F",
         "#000094",
         "#000099",
         "#00009E",
         "#0000A3",
         "#0000A8",
         "#0000AD",
         "#0000B3",
         "#0000B8",
         "#0000BD",
         "#0000C2",
         "#0000C7",
         "#0000CC",
         "#0000D1",
         "#0000D6",
         "#0000DB",
         "#0000E0",
         "#0000E6",
         "#0000EB",
         "#0000F0",
         "#0000F5",
         "#0000FA",
         "#0000FF"]

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


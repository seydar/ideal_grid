module GUI
  module Grid

    def plot_grid
      plot_edges
      plot_points
      plot_generators
    end

    def plot_flows(n: 10, labels: nil)
      flows = @grid.flows || {}

      unless flows.empty?
        max, min = flows.values.max || 0, flows.values.min || 0
        splits = n.times.map {|i| (max - min) * i / n.to_f + min }
        splits = [*splits, [flows.values.max || 0, max].max + 1]

        # low to high, because that's how splits is generated
        percentiles = splits.each_cons(2).map do |bottom, top|
          flows.filter {|e, f| f >= bottom && f < top }.map {|e, f| e }
        end


        colors = BLUES.reverse + REDS
        percentiles.each.with_index do |pc, i|
          rhea = labels ? pc.map {|e| flows[e].round(2) } : []
          plot_edges pc, :color  => colors[((i + 1) * colors.size) / (n + 1)],
                         :width  => (i + 1 * 8.0 / n),
                         :labels => rhea
        end
      end

      # Plot the untread edges to see if there are any even breaks in the grid
      edges = @grid.graph.nodes.map {|n| n.edges }.flatten.uniq
      untread = edges - flows.keys
      plot_edges untread, :color => 0x00ffff

      plot_points
      plot_generators
    end

    def plot_edges(edges=nil, color: 0x000000, width: 2, labels: [])
      edges ||= @grid.nodes.map(&:edges).flatten
      edges.zip(labels).each do |edge, label|
        from, to = *edge.nodes
        line(@margin + from.x, @margin + from.y,
             @margin + to.x,   @margin + to.y) {
          stroke color, thickness: width
        }

        if label
          # TODO
        end
      end
    end

    def plot_point(node, color: {r: 202, g: 102, b: 205, a: 0.5})
      circle(@margin + node.x, @margin + node.y, 3) {
        color.is_a?(Hash) ? fill(**color) : fill(color)
        stroke 0x000000, thickness: 2
      }
    end

    def plot_points(points=nil)
      points ||= @grid.nodes
      points.each do |node|
        plot_point node, color: 0xaaaaaa
      end
    end

    def plot_generators
      @grid.generators.each do |gen|
        plot_point gen.node, color: 0xff0000
      end
    end
  end
end

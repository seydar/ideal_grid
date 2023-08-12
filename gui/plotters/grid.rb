module GUI
  module Grid

    def grid_description
      tx_loss, perc = @grid.transmission_loss

      ["Grid range:\t#{@dimensions[0]} x #{@dimensions[1]}",
       "Nodes:\t\t#{@grid.nodes.size}",
       "Edges:\t\t#{@grid.edges.size}",
       "Total load:\t#{(@grid.loads.sum(&:load) + tx_loss).round 2}",
       "Tx loss:\t\t#{tx_loss.round 2} (#{perc}%)",
       "Freq:\t\t#{(Flow::BASE_FREQ + @grid.freq).round(2)} Hz (#{@grid.freq.round 2} Hz)"
      ].join "\n"
    end

    def plot_grid
      plot_edges
      plot_points
      plot_generators
    end

    def plot_flows(scale: [1, 1], n: 10, labels: nil)
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
                         :labels => rhea,
                         :scale  => scale
        end
      end

      # Plot the untread edges to see if there are any even breaks in the grid
      edges = @grid.graph.nodes.map {|n| n.edges }.flatten.uniq
      untread = edges - flows.keys
      plot_edges untread, :scale => scale, :color => 0x00ffff

      plot_edges @new_edges, :scale => scale, :color => 0x18cf00, :width => 6.0

      plot_points scale: scale
      plot_generators scale: scale
    end

    def plot_edges(edges=nil, scale: [1, 1], color: 0x000000, width: 2, labels: [])
      edges ||= @grid.edges
      edges.zip(labels).each do |edge, label|
        from, to = *edge.nodes
        line(@margin + from.x * scale[0], @margin + from.y * scale[1],
             @margin + to.x * scale[0],   @margin + to.y * scale[1]) {
          stroke color, thickness: width
        }

        if label
          # TODO
        end
      end
    end

    def plot_point(node, scale: [1, 1], color: {r: 202, g: 102, b: 205, a: 0.5})
      circle(@margin + node.x * scale[0], @margin + node.y * scale[1], 3) {
        color.is_a?(Hash) ? fill(**color) : fill(color)
        stroke 0x000000, thickness: 2
      }
    end

    def plot_points(points=nil, scale: [1, 1])
      points ||= @grid.nodes
      points.each do |node|
        plot_point node, scale: scale, color: 0xaaaaaa
      end
    end

    def plot_generators(scale: [1, 1])
      @grid.generators.each do |gen|
        plot_point gen.node, color: 0xff0000, scale: scale
      end
    end

    def plot_area(x: nil, y: nil, xs: 3, ys: 2)
      @plot = area {
        if x && y
          left x; xspan xs
          top  y; yspan ys
        end

        on_draw {|area|
          @dimensions = [area[:area_width], area[:area_height]]
          self.desc = grid_description

          scale = [area[:area_width]  / GridOperator::PLOT[0],
                   area[:area_height] / GridOperator::PLOT[1]]

          #rectangle(0, 0, *GridOperator::PLOT) {
          rectangle(0, 0, area[:area_width], area[:area_height]) {
            fill 0xffffff
          }

          plot_flows scale: scale
        }
      }
    end
  end
end

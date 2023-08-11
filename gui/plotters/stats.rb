require 'histogram/array'

module GUI
  module Grid
    X_OFF_LEFT   = 30
    Y_OFF_TOP    = 20
    X_OFF_RIGHT  = 20
    Y_OFF_BOTTOM = 40
    HIST_WIDTH   = 250
    HIST_HEIGHT  = 150
    POINT_RADIUS = 5
    COLOR_BLUE   = Glimmer::LibUI.interpret_color(0x1E90FF)

    def graph_size(area_width, area_height)
      graph_width = area_width - X_OFF_LEFT - X_OFF_RIGHT
      graph_height = area_height - Y_OFF_TOP - Y_OFF_BOTTOM
      [graph_width, graph_height]
    end
    
    def scale_x(bins, width, bar_width)
      scale = (width - (1.25 * bar_width)) / bins.max
      bins.map do |bin|
        scale * bin
      end
    end

    def scale_y(freqs, height)
      peak = 0.75 # how much of the graph should the peak take up
      scale = height * 0.75 / freqs.max
      freqs.map do |freq|

        # have to invert because the y axis is inverted from standard graphs
        # because that's how GUIs work
        height - freq * scale
      end
    end
    
    # method-based custom control representing a graph path
    def graph_path(width, height, should_extend, &block)
      locations = point_locations(width, height).flatten
      path {
        if should_extend
          polygon(locations + [width, height, 0, height])
        else
          polyline(locations)
        end
        
        # apply a transform to the coordinate space for this path so (0, 0) is the top-left corner of the graph
        transform {
          translate X_OFF_LEFT, Y_OFF_TOP
        }
        
        block.call
      }
    end

    # God this code is so bad
    def bar_graph(data, width, height, bar_width, &block)

      path {
        bins, freqs = @grid.flows.values.histogram

        data.zip(bins.zip(freqs)).each do |(x, y), (bin, freq)|
          rectangle(x, y, bar_width, height - y)

          # X value labeling
          text(x + bar_width / 4 - 1, height + 3) { string bin.round(1).to_s }

          # Y value labeling
          text(x + bar_width / 4 - 1, y - 20) { string freq.to_i.to_s }
        end

        transform {
          translate X_OFF_LEFT, Y_OFF_TOP
        }

        block.call
      }
    end

    def congestion_hist(x: nil, y: nil, xs: 2, ys: 3)

      @hist = area {
        if x && y
          left x; xspan xs
          top  y; yspan ys
          vexpand true
        end

        on_draw do |area|
          #rectangle(0, 0, HIST_WIDTH, HIST_HEIGHT) {
          rectangle(0, 0, area[:area_width], area[:area_height]) {
            fill 0xFFFFFF
          }
          
          #graph_width, graph_height = *graph_size(HIST_WIDTH, HIST_HEIGHT)
          graph_width, graph_height = *graph_size(area[:area_width], area[:area_height])
        
          # frame of the graph
          figure(X_OFF_LEFT, Y_OFF_TOP) {
            line(X_OFF_LEFT, Y_OFF_TOP + graph_height)
            line(X_OFF_LEFT + graph_width, Y_OFF_TOP + graph_height)
            
            stroke 0x000000, thickness: 2, miter_limit: 10
          }


          # Bars
          if @grid.flows && !@grid.flows.empty?
            bins, freqs = @grid.flows.values.histogram
            bar_width = ((graph_width / bins.size) * 0.8).floor

            bins  = scale_x bins, graph_width, bar_width
            freqs = scale_y freqs, graph_height

            bar_graph(bins.zip(freqs), graph_width, graph_height, bar_width) {
              stroke COLOR_BLUE.merge(thickness: 2, miter_limit: 10)
              fill COLOR_BLUE.merge(a: 0.5)
            }
          end

          # Title
          text(HIST_WIDTH / 2,
               Y_OFF_TOP / 2) {
            string "Histogram of Line Congestion"
          }

          # Axes
          # X axis
          text(graph_width / 2 - 2 * X_OFF_LEFT,
               graph_height + Y_OFF_TOP + 17) {
            string "Congestion (MW through lines)"
          }

          # Y axis
          path {
            text(X_OFF_LEFT / 2,
                 graph_height / 2 + Y_OFF_TOP) {
              string "# of lines"
            }

            transform {
              rotate(X_OFF_LEFT / 2 + 2,
                     graph_height / 2 + Y_OFF_TOP + 10,
                     -90)
            }
          }
        end
      }
    end

    def basic_info(x: nil, y: nil, xs: 4, ys: 1)
      label {
        if x && y
          left x; xspan xs
          top  y; yspan ys
          hexpand true
        end

        text <=> [self, :desc]
      }
    end
  end
end


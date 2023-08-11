module GUI
  module Grid

    def new_grid_buttons(x: nil, y: nil)
      form {
        left x; xspan 1
        top  y; yspan 1
        hexpand false

        entry {
          label 'Nodes'
          text <=> [self, :nodes, on_write: :to_i, on_read: :to_s]
        }
      }

      form {
        left (x + 1); xspan 1
        top   y     ; yspan 1
        hexpand false
    
        entry {
          label 'Clusters'
          text <=> [self, :clusters, on_write: :to_i, on_read: :to_s]
        }

      }

      form {
        left (x + 2); xspan 1
        top   y     ; yspan 1
        
        hexpand false

      }

      button('New Grid') {
        left x     ; xspan 2
        top (y + 1); yspan 1
        
        hexpand false
        vexpand false

        on_clicked {
          plot = GridOperator::PLOT
          range = [plot[0] - 2 * @margin, plot[1] - 2 * @margin]
          @grid = mst_grid :number   => @nodes,
                           :grouping => @clusters,
                           :range    => range
          self.desc = grid_description
          @plot.queue_redraw_all if @plot
          @hist.queue_redraw_all if @hist
        }
      } # button
    end
  end
end


module GUI
  module Grid

    attr_accessor :num_nodes
    attr_accessor :clusters
    attr_accessor :load

    def new_grid_buttons(x: nil, y: nil)
      form {
        left x; xspan 1
        top  y; yspan 1

        entry {
          label 'Nodes'
          text <=> [self, :num_nodes, on_write: :to_i, on_read: :to_s]
        }
      }

      form {
        left (x + 1); xspan 1
        top   y     ; yspan 1
    
        entry {
          label 'Clusters'
          text <=> [self, :clusters, on_write: :to_i, on_read: :to_s]
        }
      }

      form {
        left (x + 2); xspan 1
        top   y     ; yspan 1
      }

      form {
        left  x     ; xspan 1
        top  (y + 1); yspan 1
    
        entry {
          label 'MW load/node'
          text <=> [self, :load, on_write: :to_i, on_read: :to_s]
        }
      }

      button('New Grid') {
        left (x + 1); xspan 1
        top  (y + 1); yspan 1

        on_clicked {
          plot = GridOperator::PLOT
          range = [plot[0] - 2 * @margin, plot[1] - 2 * @margin]
          @grid = mst_grid :number   => @num_nodes,
                           :grouping => @clusters,
                           :draw     => @load,
                           :range    => range
          refresh!
        }
      } # button

      button("Reduce Congestion") {
        left (x + 1); xspan 1
        top  (y + 2); yspan 1

        on_clicked {
          self.potential_edges = reduce_congestion
        }
      }
    end
  end
end


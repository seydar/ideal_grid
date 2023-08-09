#!/usr/bin/env ruby --yjit -W0

require_relative "../electric_avenue.rb"
require 'glimmer-dsl-libui'
Dir['./gui/plotters/**/*.rb'].each {|f| require f }


class GridOperator
  include Glimmer
  include GUI::Grid

  MARGIN   = 20
  CONTROLS = 150
  PLOT     = [800, 500]
  LEFT     = 200
  WIDTH    = LEFT + PLOT[0] + 3 * MARGIN
  HEIGHT   = CONTROLS + PLOT[1] + 2 * MARGIN

  attr_accessor :nodes
  attr_accessor :clusters
  attr_accessor :grid
  attr_accessor :status

  def initialize
    @nodes = 500
    @clusters = 30
    @grid = Grid.new [], []
    @status = ""
  end

  def launch
    window('Electric Avenue', WIDTH, HEIGHT) {
      margined true
    
      horizontal_box {
        vertical_box {
          non_wrapping_multiline_entry {
            read_only true
            text <=> [self, :status]
          }

          form {
            stretchy false

            entry {
              label 'Nodes'
              text <=> [self, :nodes, on_write: :to_i, on_read: :to_s]
            }
    
            entry {
              label 'Clusters'
              text <=> [self, :clusters, on_write: :to_i, on_read: :to_s]
            }
          }
    
          button('New Grid') {
            stretchy false
    
            on_clicked {
              @grid = mst_grid :number   => nodes,
                               :grouping => clusters,
                               :range    => PLOT
              @grid.calculate_flows!
              @plot.queue_redraw_all
            }
          } # button
        } # vert
    
        vertical_box {
          stretchy false

          @plot = area {

            @margin = MARGIN / 2 # internal margin within the plot

            rectangle(0, 0, PLOT[0] + 2 * @margin, PLOT[1] + 2 * @margin) {
              fill 0xffffff
            }
    
            on_draw {
              plot_flows
            }
    
          } # area

          non_wrapping_multiline_entry {
            read_only true
            text "asdf"
          }
        } # vert
      }
    }.show
  end
end

GridOperator.new.launch


#!/usr/bin/env ruby --yjit -W0

require_relative "../electric_avenue.rb"
require 'glimmer-dsl-libui'
Dir['./gui/plotters/**/*.rb'].each {|f| require f }

class GridOperator
  include Glimmer
  include GUI::Grid

  MARGIN   = 20
  CONTROLS = 310
  PLOT     = [1000, 500]
  TABLE    = 200
  WIDTH    = TABLE + PLOT[0] + 2 * MARGIN
  HEIGHT   = CONTROLS + PLOT[1] + 2 * MARGIN

  attr_accessor :desc

  def refresh!
    @plot.queue_redraw_all
    @hist.queue_redraw_all
    self.desc = grid_description
  end


  def initialize
    @nodes = 800
    @clusters = 80
    @load = 10
    @grid = Grid.new [], []
    @dimensions = PLOT
    @desc = grid_description
    @margin = MARGIN / 2
    @potential_edges = []
    @new_edges = []
  end

  def launch
    window("Electric Avenue", WIDTH, HEIGHT, true) {
      margined true

      grid {

        new_grid_buttons x: 0, y: 1

        basic_info x: 0, xs: 2,
                   y: 4, ys: 1

        congestion_hist x: 2, xs: 2,
                        y: 0, ys: 6

        label { left 0; xspan 2
                top  5; yspan 1 }

        label { left 0; xspan 2
                top  5; yspan 1 }

        #horizontal_box {
        #  left 0; xspan 3
        #  top  6; yspan 3

        cong_reduc_table x: 0, xs: 1,
                         y: 6, ys: 3

        plot_area  x: 1, xs: 3,
                   y: 6, ys: 3
        #}
      }

    }.show
  end
end

GridOperator.new.launch


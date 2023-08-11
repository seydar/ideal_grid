#!/usr/bin/env ruby --yjit -W0

require_relative "../electric_avenue.rb"
require 'glimmer-dsl-libui'
Dir['./gui/plotters/**/*.rb'].each {|f| require f }

class GridOperator
  include Glimmer
  include GUI::Grid

  MARGIN   = 20
  CONTROLS = 310
  PLOT     = [800, 500]
  WIDTH    = PLOT[0] + 2 * MARGIN
  HEIGHT   = CONTROLS + PLOT[1] + 2 * MARGIN

  attr_accessor :desc

  def initialize
    @nodes = 500
    @clusters = 30
    @load = 10
    @grid = Grid.new [], []
    @dimensions = PLOT
    @desc = grid_description
    @margin = MARGIN / 2
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
                top  3; yspan 1 }

        label { left 0; xspan 2
                top  5; yspan 1 }

        label { left 0; xspan 2
                top  5; yspan 1 }

        plot_area  x: 0, xs: 3,
                   y: 6, ys: 3
      }

    }.show
  end
end

GridOperator.new.launch


#!/usr/bin/env ruby --yjit

require_relative "../electric_avenue.rb"
require 'glimmer-dsl-libui'

class GridOperator
  include Glimmer

  SIZE = 500

  attr_accessor :nodes
  attr_accessor :clusters
  attr_accessor :grid

  def initialize
    @nodes = 500
    @clusters = 30
    @grid = Grid.new [], []
  end

  def launch
    window('Electric Avenue', 1000, 1000) {
      margined true
    
      vertical_box {
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
            @grid = mst_grid :number => nodes, :grouping => clusters, :range => SIZE
            @area.queue_redraw_all
          }
        }
    
        @area = area {
          square(0, 0, SIZE) {
            fill r: 230, g: 230, b: 230
          }
    
          on_draw {
            @grid.nodes.each do |node|
              circle(node.x, node.y, 3) {
                fill r: 202, g: 102, b: 205, a: 0.5
                stroke r: 0, g: 0, b: 0, thickness: 2
              }
            end

            @grid.nodes.map(&:edges).flatten.each do |edge|
              from, to = *edge.nodes
              line(from.x, from.y, to.x, to.y) {
                stroke r: 50, g: 50, b: 50, thickness: 2
              }
            end
          }
    
        }
      }
    }.show
  end
end

GridOperator.new.launch


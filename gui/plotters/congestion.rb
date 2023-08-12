module GUI
  module Grid
    attr_accessor :potential_edges
    attr_accessor :cong_selection

    Congestion = Struct.new(:edges, :length, :tx_loss, :candidates)

    def reduce_congestion(edge_limit=4)
      scale = @dimensions.avg / 12
      new_edges = @grid.reduce_congestion :distance => 0.75 * scale

      # Hard ceiling on the edge length
      candidates = new_edges.map {|_, _, e, _| e.length < (0.5 * scale) ? e : nil }.compact
      candidates = candidates.uniq {|e| e.nodes.map(&:id).sort }
      pp candidates

      # potentially thousands of trials to run
      # We're only interested in building up to `edge_limit` edges here, since
      # we're trying to show bang for buck
      trials = (1..edge_limit).map {|i| candidates.combination(i).to_a }.flatten(1)

      puts "\tMax # of edges to build: #{edge_limit}"
      puts "\t#{candidates.size} candidates, #{trials.size} trials"

      if not trials.empty?

        # Test out each combination.
        # Detaching the edges in another process is unnecessary since the grid object
        # is copied (and thus the main processes's grid is unaffected), but the code is
        # included because it's cheap and is required for single-threaded ops
        results = trials.parallel_map do |cands|
          cands.each {|e, _, _| e.attach! }
          @grid.reset!
          cands.each {|e, _, _| e.detach! }

          @grid.transmission_loss[1]
        end
        results = trials.zip results

        # minimize tx loss, minimize total edge length
        ranked = results.sort_by do |cs, l|
          l ** 1.35 + l * cs.sum(&:length)
        end

        puts "\tRanked them!"
        ranked.map do |cs, l|
          Congestion.new cs.size, cs.sum(&:length).round(2), l.round(2), cs
        end
      else
        puts "oh well"
        []
      end
    end

    def cong_reduc_table(x: nil, y: nil, xs: 1, ys: 2)
      table {
        if x && y
          left x; xspan xs
          top  y; yspan ys
        end

        text_column "Edges"
        text_column "Length"
        text_column "Tx Loss"

        cell_rows <=> [self, :potential_edges]

        on_selection_changed do |_, selection, _, _|
          # Handle selecting
          if @current_selection
            cong = potential_edges[@current_selection]
            cong.candidates.each(&:detach!)
          end

          # Handle deselecting
          @current_selection = selection
          if selection
            cong = potential_edges[@current_selection]
            cong.candidates.each(&:attach!)

            @new_edges = cong.candidates
          else
            @new_edges = []
          end

          a = Time.now
          @grid.reset!
          puts "#{Time.now - a} to reset"

          refresh!
        end
      }
    end
  end
end


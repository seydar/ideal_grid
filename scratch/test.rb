require_relative '../lib/monkey_patch.rb'
Dir['./lib/**/*.rb'].each {|f| require f }

# NH/VT
NH_VT = {:n =>  44.1793, :s =>  43.8583,
         :e => -71.8985, :w => -72.2598}

# New England
NEW_ENGLAND_CENTRAL = {:n =>  45.01, :s =>  42.71,
                       :e => -71.01, :w => -73.25}
NEW_ENGLAND = {:n =>  47.45, :s =>  40.94,
               :e => -66.85, :w => -73.45}

# Michigan
MICHIGAN = {:n =>  45.82, :s =>  41.80,
            :e => -82.72, :w => -86.12}

grid = Grid.within NEW_ENGLAND
plot_grid grid
show_plot

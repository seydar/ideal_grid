#!/bin/zsh

# Loads
ruby script/load_caiso.rb
ruby script/load_miso.rb
ruby script/load_isone.rb

# Sources
ruby script/load_gens.rb

# Lines
ruby script/load_lines.rb data/new_england_tx_lines.geojson
ruby script/load_lines.rb data/michigan_lines.geojson

# Joining them all
#
# 3/18 only the points within NEW_ENGLAND have been joined
ruby script/join_points.rb


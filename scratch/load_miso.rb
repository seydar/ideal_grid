require_relative "../lib/db.rb"
require 'json'

# Here's how you use `cs2cs`:
#
#   echo "3458305 5428192" | cs2cs -f '%.10f' +init=EPSG:31467 +to +init=EPSG:4326 -
#   echo "8.4293092923 48.9896114523" | cs2cs -f '%.10f' +init=EPSG:4326 +to +init=EPSG:31467 -

# I think this list might be incomplete.
path = '/Users/ari/src/ideal_grid/data/miso_nodes.json' 
json = JSON.load File.read(path)
points = json['f'].map {|f| f['g']['c'] }

# Unfortunately, we have to route this to `cs2cs` because I can't get proj to
# work on my Apple M1.
open "/tmp/points.txt", "w" do |f|
  points.each do |pt|
    f.puts pt.join(' ')
  end
end

converted = `cat /tmp/points.txt | cs2cs -f '%.10f' +init=EPSG:31467 +to +init=EPSG:4326 -`
converted = converted.split("\n").map {|l| l.split(" ")[0..1].map(&:to_f) }
names = json['f'].map {|f| f['p'][0] }
pairs = names.zip converted

pairs.each do |name, (lon, lat)|
  Load.create :name => name, :region => "MISO", :lon => lon, :lat => lat
end

require 'pry'
binding.pry


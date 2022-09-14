require 'parallel'

if RUBY_VERSION < "3.0.0"
  require 'math'
end

module Enumerable
  def parallel_map(cores: 4, &block)
    n = self.size / cores
    Parallel.map(self.each_slice(n).to_a, :in_processes => cores) do |group|
      group.map(&block)
    end.flatten 1
  end
end

def dist(p1, p2)
  Math.sqrt((p1[0] - p2[0]) ** 2 + (p1[1] - p2[1]) ** 2)
end

num   = ARGV[0] ? ARGV[0].to_i : 80
prng  = Random.new 54
nodes = num.times.map { [10 * prng.rand, 10 * prng.rand] }
pairs = nodes.combination 2

puts "#{pairs.size} pairs"

block = proc do |p_1, p_2|
  sleep 0.01
  dist p_1, p_2
end

start = Time.now
dists = pairs.parallel_map(:cores => 4, &block)
puts "4 cores: #{Time.now - start}"

start = Time.now
pairs.map(&block)
puts "Single threaded: #{Time.now - start}"


require 'parallel'

module Enumerable
  def parallel_map(cores: 4, &block)
    n = size / cores
    Parallel.map each_slice(n).to_a, :in_processes => cores do |group|
      group.map(&block)
    end.flatten 1
  end

  # Shift the work to be done in parallel in #parallel_map, but then we
  # have to use a sequential filter anyways
  def parallel_filter(cores: 4, &block)
    pairs = zip parallel_map(:cores => cores, &block)
    pairs.filter {|item, test| test }.map {|i, t| i }
  end

  # Partitions based on the block. O(4n), but at least it's parallelized
  # [trues, falses]
  def parallel_partition(cores: 4, &block)
    pairs  = zip parallel_map(:cores => cores, &block)
    trues  = pairs.filter {|item, test| test }.map {|i, t| i }
    falses = pairs.filter {|item, test| not test }.map {|i, t| i }
    [trues, falses]
  end
end

# unfortunate variable shadowing
def time(phrase, &block)
  start = Time.now
  block.call
  puts "#{phrase} (#{Time.now - start})"
end

def track(var, &block)
  start = Time.now
  block.call
  eval "#{var} ||= 0; #{var} += Time.now - start"
end


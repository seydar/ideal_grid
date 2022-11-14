require 'parallel'

module Enumerable
  def parallel_map(cores: 3, &block)
    n = (size.to_f / cores).ceil

    Parallel.map each_slice(n).to_a, :in_processes => cores do |group|
      group.map(&block)
    end.flatten 1
  end

  # Shift the work to be done in parallel in #parallel_map, but then we
  # have to use a sequential filter anyways
  def parallel_filter(cores: 3, &block)
    pairs = zip parallel_map(:cores => cores, &block)
    pairs.filter {|item, test| test }.map {|i, t| i }
  end

  # Partitions based on the block. O(4n), but at least it's parallelized
  # [trues, falses]
  def parallel_partition(cores: 3, &block)
    pairs  = zip parallel_map(:cores => cores, &block)
    trues  = pairs.filter {|item, test| test }.map {|i, t| i }
    falses = pairs.filter {|item, test| not test }.map {|i, t| i }
    [trues, falses]
  end
end

# unfortunate variable shadowing
def time(phrase, &block)
  puts phrase
  start = Time.now
  res = block.call
  puts "  => (#{Time.now - start})"
  res
end

def track(var, &block)
  start = Time.now
  res = block.call
  eval "#{var} ||= 0; #{var} += Time.now - start"
  res
end

class Array
  def avg
    sum / size.to_f
  end
end


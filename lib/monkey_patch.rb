require 'parallel'
require 'matrix_boost'

module Enumerable
  def parallel_map(cores: $parallel, &block)
    return map(&block) unless $parallel

    n = (size.to_f / cores).ceil

    Parallel.map each_slice(n).to_a, :in_processes => cores do |group|
      group.map(&block)
    end.flatten 1
  end

  # Shift the work to be done in parallel in #parallel_map, but then we
  # have to use a sequential filter anyways
  def parallel_filter(cores: $parallel, &block)
    return filter(&block) unless $parallel

    pairs = zip parallel_map(:cores => cores, &block)
    pairs.filter {|item, test| test }.map {|i, t| i }
  end

  # Partitions based on the block. O(4n), but at least it's parallelized
  # [trues, falses]
  def parallel_partition(cores: $parallel, &block)
    return partition(&block) unless $parallel

    pairs  = zip parallel_map(:cores => cores, &block)
    trues  = pairs.filter {|item, test| test }.map {|i, t| i }
    falses = pairs.filter {|item, test| not test }.map {|i, t| i }
    [trues, falses]
  end
end

# unfortunate variable shadowing
def time(phrase, run: true, &block)
  return unless run

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


class Matrix
  def *(m)
    MatrixBoost.multiply self, m
  end

  def **(n)
    res = self
    n.times { res = self * res }
    res
  end

  # Reminder: there's no good reason to ever invert a matrix.
  #
  # Sparse matrix? Inversion will be dense.
  #
  # Solving a system of equations? Use Gauss-Jordan elimination to compute
  # the reduced row echelon form (RREF).
  def inverse
    MatrixBoost.inverse self
  end
end


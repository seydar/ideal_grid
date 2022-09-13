require 'parallel'

module Enumerable
  def parallel_map(cores: 4, &block)
    n = self.size / cores
    Parallel.map(self.each_slice(n).to_a, :in_processes => cores) do |group|
      group.map(&block)
    end.flatten 1
  end
end


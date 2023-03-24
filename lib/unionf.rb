# https://github.com/schweigert/Unionf/blob/master/lib/unionf.rb
# from schweigert (Marlon Henry Schweigert)

class UnionF
  attr_accessor :id

  def self.mark(elts, &test)
    uf = new elts
    (0..elts.size - 1).each do |i|
      (i + 1..elts.size - 1).each do |j|
        uf.union elts[i], elts[j] if test.call(elts[i], elts[j])
      end
    end

    uf
  end

  def initialize elements
    @id = {}
    @sz = {}
    @el = []
    elements.each {|n| @id[n] = n; @sz[n] = 1; @el << n }
  end

  def roots
    @id.values.uniq
  end

  def disjoint_sets
    #@id.keys.group_by {|a| @id[a] }.values
    hash = {}
    @id.keys.each {|k| (hash[find k] ||= []) << k }
    hash.values
  end
  alias_method :connected_subgraphs, :disjoint_sets

  def connected? a, b
    a, b = pair_search a, b
    a == b
  end

  def union a, b
    a, b = pair_search a, b

    return if a == b or a.nil? or b.nil?

    a, b = b, a if @sz[a] >= @sz[b]

    @id[a] = b
    @sz[a] += @sz[b]
    @sz[b] = @sz[a]
  end

  # I think the path compression is not great here. I have to look up
  # every element again in order to do full path compression in order to get
  # the disjoint sets
  def find a
    return a if @id[a] == a
    @id[a] = find @id[a]
  end

  def size
    @id.size
  end

  def size? a
    a = find a
    @sz[a]
  end

  def elements
    @el
  end

  def pair_search a, b
    a = find a
    b = find b
    [a, b]
  end
end


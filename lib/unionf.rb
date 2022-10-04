# https://github.com/schweigert/Unionf/blob/master/lib/unionf.rb
# from schweigert (Marlon Henry Schweigert)

class UnionF

  def initialize elements
    @id = {}
    @sz = {}
    @el = []
    elements.each {|n| @id[n] = n; @sz[n] = 1; @el << n}
  end

  def roots
    @id.values.uniq
  end

  def disjoint_sets
    @id.keys.group_by {|a| @id[a] }.values
  end
  alias_method :connected_subgraphs, :disjoint_sets

  def connected? a, b
    a, b = pair_search a, b
    a == b
  end

  def union a, b
    a, b = pair_search a, b

    return if a == b or a.nil? or b.nil?

    a, b = b, a if @sz[a] > @sz[b]

    @id[a] = b
    @sz[a] += @sz[b]
    @sz[b] = @sz[a]
  end

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

  private

  def pair_search a, b
    a = find a
    b = find b
    [a,b]
  end

end


class Edge
  attr_accessor :nodes # guaranteed to be #size == 2
  attr_accessor :length
  attr_accessor :id
  attr_accessor :flow
  attr_accessor :voltage

  # literally just pulling this out of my ass
  # https://skm-eleksys.com/2011/03/transmission-line-parameters-resistance.html
  # Plus, it'll be multiplied by the length of the line
  #
  # https://www.midalcable.com/sites/default/files/ACSR-metric.PDF
  #
  # Using "quail" from the above link.
  # I will pretend that each edge length is in km
  R_I_a = 0.4247 # Ohm / km

  # TODO Make this all named parameters
  def initialize(to, from, length=0, id: nil, voltage: nil)
    raise "Don't be a fool! Use an ID!" unless id
    @length  = length
    @nodes   = [to, from]
    @id      = id
    @flow    = {}
    @voltage = voltage
  end

  # one day this will have more meaning
  def resistance
    length * R_I_a
  end

  # Joule's effect (in reference to Joule heating,
  # https://en.wikipedia.org/wiki/Joule_heating) says that we're going to lose
  # power to heating, since transmission lines will have non-zero resistance.
  #   P = I^2 * R
  # Thus, the cost is going to be proportional to the square of the current (flow)
  #
  # Not currently using but would be good:
  #   https://www.unioviedo.es/pcasielles/uploads/proyectantes/cosas_lineas.pdf
  #
  # Ignoring:
  #   - frequency effect
  #     (since all lines will be assumed to be the same voltage -- I'm looking
  #     at transmission lines, not distribution lines)
  #   - temperature effect
  #     because I'm lazy and don't think it'll have a big effect
  #   - noise
  #     Johnson-Nyquist effect. because I think it'll be minor
  #   - reactive power
  #     should prolly add this in
  def power_loss(flow)
    resistive_loss(flow)
  end

  def resistive_loss(flow)
    flow ** 2 * R_I_a * length * 1e-3 # 1e-3 because our flow is in units of kA
  end

  # Calculate flow given a loss
  def inverse_loss(loss)
    Math.sqrt(loss / (R_I_a * length * 1e-3))
  end

  def mark_nodes!
    nodes.each {|n| n.edges << self unless n.edges.include?(self) }
  end
  alias_method :attach!, :mark_nodes!

  def detach!
    nodes.each do |node|
      node.edges = node.edges.reject {|e| e == self }
    end
  end

  # mistakenly created an edge from a node to itself
  def possible?
    nodes[0] != nodes[1]
  end

  # Are the nodes already marked?
  def exists?
    # do we already exist?
    nodes.all? {|n| n.edges.include? self }
  end

  def not_node(node)
    (nodes - [node])[0]
  end

  def replace(old, new)
    return unless @nodes.include? old
    @nodes.delete(old)
    @nodes << new
    @nodes
  end

  def inspect
    n1 = nodes[0].to_a.map {|v| v.round 3 }
    n2 = nodes[1].to_a.map {|v| v.round 3 }
    "#<Edge:#{object_id} #{n1} <=> #{n2}>"
  end

  def ==(other)
    return false unless other.is_a? Edge
    id == other.id
  end

  # https://en.wikipedia.org/wiki/Distance_from_a_point_to_a_line#Line_defined_by_two_points
  def ray_distance_to_point(p0)
    p1, p2 = *nodes
    numerator   = (((p2.x - p1.x) * (p1.y - p0.y)) - ((p1.x - p0.x) * (p2.y - p1.y))).abs
    denominator = Math.sqrt((p2.x - p1.x) ** 2 + (p2.y - p1.y) ** 2)

    numerator / denominator
  end
end


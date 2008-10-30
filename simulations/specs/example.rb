class Example < Sim::Specification

  def execute(sim)
    g = Sim::Graph.new
    g.edge 1 => 2
    sim.events = g.events
    sim.nodes.router :epidemic

    data = 'a' * variants(:size, 1024, 1024000)

    sim.at(variants(:sendRate, 3600, 360)) do |time|
      sim.node(1).sendDataTo(data, 'dtn://kasuari2/')
      # run for one day
      time < 3600*24
    end
  end
end

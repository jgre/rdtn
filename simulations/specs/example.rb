class Example < Sim::Specification

  def execute(sim)
    g = Sim::Graph.new
    g.edge 1 => 2
    sim.events = g.events
    sim.nodes.router :epidemic

    bogus = variants(:bogus, 1, nil)
    quatsch = variants(:quatsch, 'bla', 'fasel', 'nil')

    #data = 'a' * variants(:size, [1024, '1KB'], [1024000, '1000KB'])
    data = 'a'

    sim.at(variants(:sendRate, 3600, 360)) do |time|
      sim.node(1).sendDataTo(data, 'dtn://kasuari2/')
      # run for one day
      time < 3600*24
    end
  end

  def analyze(analysis)
    analysis.x_axis  = :sendRate
    analysis.gnuplot = true

    analysis.configure_plot do |plot|
      plot.ylabel "# Bundles"
      plot.xlabel "Send Rate"
    end

    analysis.plot :combine => :quatsch do |dataset|
      dataset.values do |row, x, network_model, traffic_model|
	row.value "delivered", traffic_model.numberOfDeliveredBundles
      end
    end
  end

end

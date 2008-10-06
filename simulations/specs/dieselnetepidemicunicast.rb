class DieselnetEpidemicUnicast

  def initialize(sim)
    sim.trace :type => 'DieselNetParser', :tracefile => 'dieselnet_spring2007'

    puts "NNodes #{sim.nodes.length}"
    puts "Duration #{sim.duration} (#{sim.duration / (24*3600)} days)"

    sim.nodes.linkCapacity = (11 * 10**6 / 8).to_i
    sim.nodes.router :epidemic

    sim.nodes.values.each {|node| node.register {}}

    data = 'a' * 100
    node_pairs = YAML.load_file('simulations/specs/node_pairs.yml')

    sim.at(3600) do |time|
      src, dest = node_pairs[rand(node_pairs.length)]
      sim.node(src).sendDataTo data, "dtn://kasuari#{dest}/"
      puts "Day #{time / (3600*24)}" if (time % (3600*24)) == 0
      time < sim.duration
    end
  end
end

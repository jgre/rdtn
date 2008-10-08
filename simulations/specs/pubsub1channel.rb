class PubSub1Channel < Sim::Specification

  def execute(sim)
    sim.trace(variants(:traces,
             {:type => 'DieselNetParser', :tracefile => 'dieselnet_spring2007'}))
             #{:type => 'MITParser',       :tracefile => 'MITcontacts.txt'}))

    sim.nodes.linkCapacity = (11 * 10**6 / 8).to_i
    sim.nodes.router :epidemic

    channel = 'dtn://channel1/'

    receiver_count = variants(:receiver_count, 1, 10, sim.nodes.length/2, 
                              sim.nodes.length)
    # Load a randomized list of node IDs
    shuffled_nodes = YAML.load_file('simulations/specs/shuffled_nodes.yml')

    # select the desired number of receivers
    i = 0
    receivers = shuffled_nodes.find_all do |n|
      sim.nodes.length >= n and (i+=1) <= receiver_count
    end
    receivers.each {|n| sim.node(n).register(channel) {}}

    # Select one sender
    sender = shuffled_nodes.find {|n| sim.nodes.length >= n}

    data = 'a' * 1024

    sim.at(3600 / variants(:sendRate, 1, 2, 10)) do |time|
      sim.node(sender).sendDataTo data, channel, nil, :multicast => true
      puts "#@var_idx Day #{time / (3600*24)}" if (time % (3600*24)) == 0
      time < sim.duration / 15
    end
  end

end

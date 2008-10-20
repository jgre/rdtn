class PubSub1Channel < Sim::Specification

  def execute(sim)
    sim.trace(variants(:traces,
            {:type => 'DieselNetParser', :tracefile => 'dieselnet_spring2007'}))
             #{:type => 'MITParser',       :tracefile => 'MITcontacts.txt'}))

    sim.nodes.linkCapacity = (11 * 10**6 / 8).to_i
    sim.nodes.router :epidemic

    channel = 'dtn://channel1/'

    receiver_count = variants(:receiver_count, 1, lambda {sim.nodes.length/2},
                              lambda {sim.nodes.length})
    # Load a randomized list of node IDs
    shuffled_nodes = YAML.load_file('simulations/specs/shuffled_nodes.yml')

    # select the desired number of receivers
    i = 0
    receivers = shuffled_nodes.find_all do |n|
      sim.nodes.length >= n and (i+=1) <= receiver_count
    end

    # seed the random number generator for deterministic results
    srand 42
    receivers.each do |n|
      subtime,unsubtime=variants(:subscriptionInterval, [0, nil],
				 [t=rand(sim.duration), t+rand(sim.duration-t)])
      sim.at(subtime) {sim.node(n).register(channel) {}; false}
      sim.at(unsubtime) {sim.node(n).unregister(channel); false} if unsubtime
    end

    # Select one sender
    sender = shuffled_nodes.reverse.find {|n| sim.nodes.length >= n}

    # Let the payload lie about its size so it doesn't consume memory and still 
    # have the right simulation effect on queuing.
    data = ''; def data.length; 1024; end

    sim.at((3600 / variants(:sendRate, (1/24.0), 1, 2, 10)).to_i) do |time|
      b = sim.node(sender).sendDataTo(data, channel, nil, :multicast => true,
				      :lifetime => 86400)
      puts "#@var_idx Day #{time / (3600*24)}" if (time % (3600*24)) == 0
      time < sim.duration
    end

  end

end

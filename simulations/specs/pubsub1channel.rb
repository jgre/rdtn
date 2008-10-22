class PubSub1Channel < Sim::Specification

  def execute(sim)
    sim.trace(variants(:traces,
            {:type => 'DieselNetParser', :tracefile => 'dieselnet_spring2007'}))
             #{:type => 'MITParser',       :tracefile => 'MITcontacts.txt'}))

    sim.nodes.linkCapacity = (11 * 10**6 / 8).to_i
    sim.nodes.router :epidemic

    channel = 'dtn://channel1/'

    receiver_count = variants(:receiver_count, lambda {sim.nodes.length/2},
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
    rnd = variants(:random_intervals, false, true)
    receivers.each do |n|
      interval = rnd ? [t=rand(sim.duration), t+rand(sim.duration-t)] : [0, nil]
      subtime,unsubtime=variants(:subscriptionInterval, interval)

      sim.at(subtime) {sim.node(n).register(channel) {}; false}
      sim.at(unsubtime) {sim.node(n).unregister(channel); false} if unsubtime
    end

    # Select one sender
    sender = shuffled_nodes.reverse.find {|n| sim.nodes.length >= n}

    # Let the payload lie about its size so it doesn't consume memory and still 
    # have the right simulation effect on queuing.
    data = ''; def data.length; 1024; end

    # Define variations for expiry: 1hour, 1day, 5days, a quota of 10 items, and
    # a quota of 20 items.
    lifetime = 0
    quota    = nil
    variants(:lifetime,
	     lambda {lifetime = 3600;   quota = nil},
	     lambda {lifetime = 86400;  quota = nil},
	     #lambda {lifeimte = 432000; quota = nil},
	     lambda {lifetime = nil;    quota = 10},
	     lambda {lifetime = nil;    quota = 20})

    # Assign the quotas to the stores of all nodes for the variants with quotas
    sim.nodes.values.each {|n| n.config.store.channelquota = quota} if quota

    sim.at((3600 / variants(:sendRate, 1, 5)).to_i) do |time|
      b = sim.node(sender).sendDataTo(data, channel, nil, :multicast => true,
				      :lifetime => lifetime)
      puts "#@var_idx Day #{time / (3600*24)}" if (time % (3600*24)) == 0
      time < sim.duration
    end

  end

end

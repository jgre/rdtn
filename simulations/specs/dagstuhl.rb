require 'statistics'

class Dagstuhl < Sim::Specification

  def execute(sim)
    sim.trace(variants(:traces,
            [{:type => 'MITParser', :tracefile => 'random_walk_ConnectivityDtnsim2Report'}, 'Random Walk'],
            [{:type => 'MITParser', :tracefile => 'jgre-wdm1_ConnectivityDtnsim2Report'}, 'WDM']))
            #{:type => 'SetdestParser', :tracefile => 'scen-s1-10000x10000-n100-m1-M19-p50-1'},
            #[{:type => 'DieselNetParser', :tracefile => 'dieselnet_spring2007'}, 'DieselNet']))
            #{:type => 'MITParser',       :tracefile => 'MITcontacts.txt'}))

    sim.nodes.linkCapacity = (2 * 10**6 / 8).to_i
    sim.nodes.router variants(:router, [:epidemic, "Epidemic Routing"])
			               #[:dpspPopularity, "DPSP (popularity)"],
				       #[:dpspShortDelay, "DPSP (short delay)"],
				       #[:dpspHopCount, "DPSP (hop count)"],
				       #[:dpsplifetime, "DPSP (bundle lifetime)"]
			     #)

    sim.nodes.storage_limit = 1024**2 * variants(:storage_limit,10, 30, 50, 256)
  
    n_channels = 5
    channels = (1..n_channels).map {|i| "dtn://channel#{i}/"}

    receiver_count = sim.nodes.length
    # Load a randomized list of node IDs
    shuffled_nodes = YAML.load_file('simulations/specs/shuffled_nodes.yml')

    # select the desired number of receivers
    i = 0
    receivers = shuffled_nodes.find_all do |n|
      sim.nodes.length >= n and (i+=1) <= receiver_count
    end

    # seed the random number generator for deterministic results
    srand 42
    #subs_lifetime = variants(:subscription_lifetime, 3600, 86400, 432000, nil)
    subs_lifetime = 86400
    receivers.each do |n|
      interval = [t=rand(sim.duration-subs_lifetime.to_i), subs_lifetime ? t+subs_lifetime : nil]
      subtime, unsubtime = interval

      # Randomly select two channels to subscribe to
      ci1 = rand(channels.length)
      ci2 = rand(channels.length)
      while ci1 == ci2; ci2 = rand(channels.length); end

      #sim.at(0)   {sim.node(n).register(channel){}; false}
      [channels[ci1], channels[ci2]].each do |channel|
	sim.at(subtime)   {sim.node(n).register(channel){}; false}
	sim.at(unsubtime) {sim.node(n).unregister(channel); false} if unsubtime
      end
    end

    # Select one sender per channel
    senders = shuffled_nodes.reverse.find_all {|n| sim.nodes.length >= n}[0, n_channels]

    # Let the payload lie about its size so it doesn't consume memory and still 
    # have the right simulation effect on queuing.
    data = ''
    # 5MB (song or short podcast), 30MB (long podcast), 50MB, 100MB (video)
    $content_size = 1024**2 * variants(:content_size, 5, 30, 50, 100
    #content_size = 5242880
    def data.bytesize
      $content_size
    end

    # Define variations for expiry: 1hour, 6 hours, 12 hours, and a quota of
    # 10 items
    lifetime = 21600 # variants(:lifetime, 3600, 21600, 43200, nil)
			       #[lifetime = 3600,   quota = nil])
			       #[lifetime = 86400,  quota = nil],
			       #[lifeimte = 432000, quota = nil],
			       #[lifetime = nil,    quota = 10],
			       #[lifetime = nil,    quota = 15]

    # Assign the quotas to the stores of all nodes for the variants with quotas
    sim.nodes.values.each{|n| n.config.store.channelquota = 15} if lifetime == 0

    sim.at(3600) do |time|
      senders.each_with_index do |sender, i|
	b = sim.node(sender).sendDataTo(data, channels[i], nil,:multicast=>true,
					:lifetime => lifetime)
      end
      puts "#@var_idx Day #{time / (3600*24)}" if (time % (3600*24)) == 0
      time < (3600 * 48) #sim.duration
    end

  end

  def analyze(analysis)
    analysis.gnuplot = true

    analysis.configure_data :combine => :router, :x_axis => :storage_limit do |row, x, network, traffic|
      row.value "delivered", traffic.numberOfDeliveredBundles
      row.value "expected (greedy)",  traffic.numberOfExpectedBundles
      #row.value "expected (opportunistic)",  traffic.numberOfExpectedBundles(:net => network)
      delays = traffic.delays
      row.value "delay", delays.mean
      row.std_error "delay", delays.sterror
    end

    analysis.plot :combine => :router, :y_axis => ["delivered", "expected (greedy)"], :only_once => ["expected (greedy)"], :x_axis => :storage_limit #do |plot|
      #plot.ylabel "# Bundles"
      #plot.xlabel "Bundle Lifetime"
    #end

    analysis.plot :combine => :router, :y_axis => ["delay"], :x_axis => :storage_limit #do |plot|
    #  plot.ylabel "delay [seconds]"
    #  plot.xlabel "Bundle Lifetime"
    #end
  end 

end

require 'statistics'

class Dagstuhl < Sim::Specification

  def execute(sim)
    puts "Simulating variant #@var_idx"

    sim.trace(:type => 'MITParser', :tracefile => 'jgre-wdm2_ConnectivityDtnsim2Report')

    sim.nodes.linkCapacity = (2 * 10**6 / 8).to_i
    sim.nodes.router(*variants(:router,
			       [[:epidemic], "Epidemic Routing"],
			       [[:dpsp, {:filters => [:knownSubscription?]}], "DPSP (known subscription filter)"],
			       [[:dpsp, {:filters => [:exceedsHopCountLimit?], :hopCountLimit => 3}], "DPSP (hop count limit 3)"],
			       [[:dpsp, {:prios => [:popularity]}], "DPSP (popularity)"],
			       [[:dpsp, {:prios => [:hopCount]}], "DPSP (hop count)"],
			       [[:dpsp, {:prios => [:shortDelay]}], "DPSP (short delay)"],
			       [[:dpsp, {:prios => [:proximity]}], "DPSP (proximity)"]))

    sim.nodes.storage_limit = 1024**2*variants(:storage_limit, 10, 30, 50, 256)
    sim.nodes.subscription_range = variants(:subscription_range, 1, 5, 10, 100)
  
    n_channels = 10
    channels = (1..n_channels).map {|i| "dtn://channel#{i}/"}

    receiver_count = sim.nodes.length

    # set a fixed duration of 2 days
    duration = 3600 * 48

    # seed the random number generator for deterministic results
    srand 42

    subs_lifetime = 86400
    (1..receiver_count).each do |n|
      # Randomly select three channels to subscribe to
      ci1 = rand(channels.length)
      ci2 = rand(channels.length/2)
      while ci1 == ci2; ci2 = rand(channels.length/2); end
      ci3 = rand(channels.length/3)
      while [ci1, ci2].include?(ci3); ci3 = rand(channels.length/3); end

      [channels[ci1], channels[ci2], channels[ci3]].each do |channel|
	subtime   = rand(duration-subs_lifetime.to_i)
        unsubtime = subtime + subs_lifetime

	sim.at(subtime)   {sim.node(n).register(channel){}; false}
	sim.at(unsubtime) {sim.node(n).unregister(channel); false}
      end
    end

    # Select one sender per channel
    senders = (1..sim.nodes.length).to_a.shuffle[0, n_channels]

    # Let the payload lie about its size so it doesn't consume memory and still 
    # have the right simulation effect on queuing.
    data = ''
    # 5MB (song or short podcast), 30MB (long podcast), 50MB, 100MB (video)
    $content_size = 1024**2 * variants(:content_size, 1) # 30, 50, 100)
    def data.bytesize
      $content_size
    end

    # Bundles expire after 6 hours
    lifetime = 21600

    senders.each_with_index do |sender, i|
      sim.at(3600 + rand(1800)) do |time|
	sim.node(sender).sendDataTo(data, channels[i], nil,:multicast=>true,
				    :lifetime => lifetime)
	time < duration
      end
    end
  end

  def analyze(analysis)
    analysis.gnuplot = true

    analysis.configure_data do |row, network, traffic|
      row.value "# delivered bundles", traffic.numberOfDeliveredBundles
      delays = traffic.delays.map {|delay| delay / 3600.0}
      row.value "delay", delays.mean
      row.std_error "delay", delays.sterror
      row.value "# contacts", network.numberOfContacts
      row.value "# bundles", traffic.numberOfExpectedBundles
      row.value "contact duration", network.averageContactDuration
      row.value "successful transmissions (MB)",traffic.bytesTransmitted/1024**2
      bufferUse = traffic.bufferUse(3600).map {|use| (use / 1024**2) / row.value(:storage_limit).to_f * 100}
      row.value "buffer use", bufferUse.mean
      row.std_error "buffer use", bufferUse.sterror
      row.value "failed transmissions (MB)", traffic.failedTransmissions/1024**2
    end

    [:storage_limit, :subscription_range].each do |x_axis|
      analysis.plot :combine => :router, :y_axis => ["# delivered bundles"], :x_axis => x_axis
      analysis.plot :combine => :router, :y_axis => ["delay"], :x_axis => x_axis
      analysis.plot :combine => :router, :y_axis => ["successful transmissions (MB)", "failed transmissions (MB)"], :x_axis => x_axis
      analysis.plot :combine => :router, :y_axis => ["buffer use"], :x_axis => x_axis
    end

  end 

end

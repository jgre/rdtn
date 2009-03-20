require 'json'

class PubSubScenario < Sim::Specification

  def execute(sim)
    sender_count     = variants :sender_count, 1, 5, 10 #, 15, 20)
    subscriber_count = variants :subscriber_count, 100 #, 200, 500, 1000)

    bundle_lifetime  = variants :bundle_lifetime, 3600 #, 21600, 43200,86400)

    mobility_model   = variants :mobility_model, "WDM" #, "RWP")

    sim.trace(:type => 'MITParser', :tracefile => "#{mobility_model}-#{sender_count}-#{subscriber_count}")
    sim.nodes.storage_limit      = 1024**2 * 20
    sim.nodes.subscription_range = 5

    sim.nodes.router(variants(:router,
                              [:epidemic]))
                              # [:dpsp, {:prios => [:shortDelay]}],
                              # [:dpsp, {:prios => [:popularity]}],
                              # [:dpsp, {:filters => [:knownSubscription?]}],
                              # [:spraywait]))
    sim.nodes.linkCapacity = (2 * 10**6 / 8).to_i

    feeds = JSON.load(File.read(File.join(File.dirname(__FILE__),"feeds.json")))
    subs  = JSON.load(File.read(File.join(File.dirname(__FILE__),
                                          "subs-#{subscriber_count}.json")))

    feeds.each do |feed_url, items|
      items.each do |item_url, item|
        data = 'a' * item['size']
        sim.at(item['published']) do |time|
          sender_count.times do |i|
            # FIXME: Addressing
            bundle = Bundling::Bundle.new(data,feed_url,nil,:multicast=>true,
                                          :lifetime => bundle_lifetime)
            sim.node("Sender#{i}").sendBundle bundle
          end
        end
      end
    end

    subs.each do |nodeid, feed_urls|
      # Add the sender_count to the node id, as ONE numbers the nodes
      # regardless of their groups
      feed_urls.each {|url| sim.node("n#{nodeid.to_i + sender_count}").register(url){}}
    end
  end

  def preprocess(variant, network, traffic)
    delays    = traffic.delays
    durations = network.contactDurations
    bufferUse = traffic.bufferUse(3600).map {|use| (use / 1024**2) / (1024**2 * 20).to_f * 100}
    ret = [
    {
      # basic traffic stats
      "Delivered Bundles" => traffic.numberOfDeliveredBundles,
      "Delivery Ratio"    => traffic.deliveryRatio,
      "Delay"             => delays.mean,
      "Delay_error"       => delays.sterror,

      # transmission stats
      "Successful Transmissions" => traffic.bytesTransmitted / 1024**2,
      "Failed Transmissions"     => traffic.failedTransmissionVolume / 1024**2,

      # network stats
      "Contact Duration"       => durations.mean,
      "Contact Duration_error" => durations.sterror,
      "Contact Count"          => network.numberOfContacts,

      # buffer use
      "Buffer Use"       => bufferUse.mean,
      "Buffer Use_error" => bufferUse.sterror,
    }]
    neighbor_counts = network.nodes.map {|node|network.neighbors(node).length}
    neighbor_counts.sort!
    neighbor_counts.each_with_index do |neighbor_count, idx|
      ret << {"# of Neighbors" => neighbor_count, :node_index => idx}
    end
    ret
  end

  def analyze(preprocessed, dir)
    translations = {[:epidemic] => "Epidemic", :sender_count => "# of Senders"}

    ["Delivered Bundles", "Delivery Ratio", "Delay", "Successful Transmissions",
     "Failed Transmissions", "Contact Duration",
     "Contact Count"].each do |y_axis|
      results = Analysis.aggregate preprocessed, :x_axis => :sender_count, :y_axis => y_axis, :combine => :router

      Analysis.plot results, :x_axis => :sender_count, :y_axis => y_axis, :dir => dir, :translate => translations
    end

    results = Analysis.aggregate preprocessed, :x_axis => :node_index, :y_axis => "# of Neighbors", :enumerate => [:sender_count]
    Analysis.plot results, :x_axis => :node_index, :y_axis => "# of Neighbors", :dir => dir, :translate => translations
  end

end

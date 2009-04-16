require 'json'
require 'ccndpsp'

class PubSubScenario < Sim::Specification

  def execute(sim)
    sender_count     = variants :sender_count, 1 #, 5, 10#, 15, 20)
    subscriber_count = variants :subscriber_count, 500 #, 1000)

    bundle_lifetime  = variants :bundle_lifetime, 3600 #, 21600, 43200,86400)
    cache_lifetime   = variants :cache_lifetime, 8*3600, nil
    mobility_model   = variants :mobility_model, "WDM" #, "RWP")

    sim.trace(:type => 'MITParser', :tracefile => "#{mobility_model}-#{sender_count}-#{subscriber_count}")
    sim.nodes.storage_limit = 1024**2 * 64
    sim.nodes.cache_limit   = 1024**2 * variants(:cache_limit, 64) #, 256)
    sim.nodes.cache_replacement = variants(:replacement_policy,:lru,:popularity)
    #sim.nodes.subscription_range = 5

    router = variants(:router,
                      [:epidemic],
                      [:ccndpsp, {:prios => [:shortDelay]}],
                      [:ccndpsp, {:prios => [:popularity]}],
                      [:ccndpsp, {:filters => [:knownSubscription?]}],
                      [:spraywait])
    #cacheCount = variants(:caches, 0, 1, 100, 1000)
    cacheCount = variants(:caches, 1000)

    pollSubs   = variants(:pollSubscriptions, nil)
    #pollSubs   = variants(:pollSubscriptions, 3600, nil)

    caches = case cacheCount
             when 0 then []
             when 1 then (1..sender_count).to_a
             when 1000 then (1..sim.nodes.length-1).to_a
             else
               (1..sender_count).to_a + (sender_count+1..sim.nodes.length-1).to_a.shuffle[0, cacheCount]
             end
    sim.nodes.each do |nodeid, node|
      /.*(\d+)/ =~ nodeid.to_s
      nodeidx = $1
      cacheSubs = caches.include? nodeidx
      router_opts = {:cacheSubscriptions => cacheSubs,
        :pollInterval => pollSubs, :bundleLifetime => bundle_lifetime}
      node.router(router[0], router_opts.merge(router[1] || {}))
    end

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
            #bundle = Bundling::Bundle.new(data,feed_url,nil,:multicast=>true,
            #:lifetime => bundle_lifetime)
            #sim.node("Sender#{i}").sendBundle bundle

            PubSub.publish(sim.node("Sender#{i}"), feed_url, data,
                           :lifetime => cache_lifetime)
          end
        end
      end
    end

    subs.each do |nodeid, feed_urls|
      # Add the sender_count to the node id, as ONE numbers the nodes
      # regardless of their groups
      feed_urls.each {|url| PubSub.subscribe(sim.node("n#{nodeid.to_i + sender_count}"), url) {}}
    end
    #TODO: register senders as internet gws
    sim.at(0) do
      sender_count.times{|i| sim.node("Sender#{i}").register("dtn:internet-gw/") {}}
    end
  end

  def preprocess(variant, network, traffic)
    delays    = traffic.contentItemDelays
    durations = network.contactDurations
    bufferUse = traffic.bufferUse(3600).map {|use| (use / 1024**2) / (1024**2 * 20).to_f * 100}
    cacheUse  = traffic.cacheUse(3600).map {|use| (use / 1024**2) / (1024**2 * 20).to_f * 100}
    ret = [
    {
      # basic traffic stats
      "Delivered Content" => traffic.deliveredContentItemCount,
      "Delivery Ratio"    => traffic.contentItemDeliveryRatio,
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

      # cache use
      "Cache Use"       => cacheUse.mean,
      "Cache Use_error" => cacheUse.sterror,
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

    ["Delivered Content", "Delivery Ratio", "Delay", "Successful Transmissions",
     "Failed Transmissions", "Contact Duration",
     "Contact Count"].each do |y_axis|
      results = Analysis.aggregate preprocessed, :x_axis => :sender_count, :y_axis => y_axis, :combine => :router

      Analysis.plot results, :x_axis => :sender_count, :y_axis => y_axis, :dir => dir, :translate => translations
    end

    results = Analysis.aggregate preprocessed, :x_axis => :node_index, :y_axis => "# of Neighbors", :enumerate => [:sender_count]
    Analysis.plot results, :x_axis => :node_index, :y_axis => "# of Neighbors", :dir => dir, :translate => translations
  end

end

require 'json'

class PubSubScenario < Sim::Specification

  def execute(sim)
    sim.nodes.linkCapacity = (2 * 10**6 / 8).to_i
    sim.nodes.router(variants(:router,
                              [:epidemic]))
                              # [:dpsp, {:prios => [:shortDelay]}],
                              # [:dpsp, {:prios => [:popularity]}],
                              # [:dpsp, {:filters => [:knownSubscription?]}],
                              # [:spraywait]))
    sender_count     = variants(:sender_count, 1, 5, 10, 15, 20)
    subscriber_count = variants(:subscriber_count, 100, 200, 500, 1000)

    bundle_lifetime  = variants :bundle_lifetime, 3600 #, 21600, 43200,86400)

    mobility_model   = variants :mobility_model, "WDM" #, "RWP")

    sim.trace(:type => 'MITParser', :tracefile => "#{mobility_model}-#{sender_count}-#{subscriber_count}")
    sim.nodes.storage_limit      = 1024**2 * 20
    sim.nodes.subscription_range = 5

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
      feed_urls.each {|url| sim.node("n#{nodeid.to_i + sender_count}").register(url)}
    end
  end

  def preprocess(variant, network, traffic)
    {:meanDelay => traffic.averageDelay}
  end

  def analyze(preprocessed, dir)
    results = Analysis.aggregate preprocessed, :x_axis => :sender_count, :y_axis => :meanDelay, :enumerate => [:routing]

    Analysis.plot results, :x_axis => :sender_count, :y_axis => :meanDelay, :dir => dir
  end

end

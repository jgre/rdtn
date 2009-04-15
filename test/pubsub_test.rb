$: << File.join(File.dirname(__FILE__), '..', 'lib')
$:.unshift File.join(File.dirname(__FILE__), '../sim/maidenvoyage')

require 'test/unit'
require 'rubygems'
require 'shoulda'
require 'pubsub'
require 'daemon'
require 'maidenvoyage'
require 'graph'
require 'spraywaitrouter'

class TestPubSub < Test::Unit::TestCase

  context 'PubSub on a single node' do

    setup do
      @daemon = RdtnDaemon::Daemon.new("dtn://receiver.dtn/")
      @store  = @daemon.config.store
      @daemon.router(:epidemic, :cacheSubscriptions => true)
      @uri    = "pubsub://test/collection"
    end

    should 'deliver published data to a subscriber' do
      received = nil
      data     = "test data"
      PubSub.publish(@daemon, @uri, data)
      PubSub.subscribe(@daemon, @uri) {|content| received = content}
      assert_equal data, received
    end

    should 'deliver published data to previously existing subscribers' do
      received = nil
      data     = "test data"
      PubSub.subscribe(@daemon, @uri) {|content| received = content}
      PubSub.publish(@daemon, @uri, data)
      assert_equal data, received
    end

    should 'deliver updated of published data to a subscriber' do
      received = nil
      rev1     = "initial revision"
      rev2     = "updated revision"
      PubSub.subscribe(@daemon, @uri) {|content| received = content}
      PubSub.publish(@daemon, @uri, rev1)
      PubSub.publish(@daemon, @uri, rev2)
      assert_equal rev2, received
    end

    should 'not deliver data that was deleted' do
      received = nil
      data     = "test data"
      PubSub.publish(@daemon, @uri, data)
      PubSub.delete(@daemon, @uri)
      PubSub.subscribe(@daemon, @uri) {|content| received = content}
      assert_nil received
    end

    should 'not deliver updates after unsubscribing' do
      received = nil
      data     = "test data"
      PubSub.subscribe(@daemon, @uri) {|content| received = content}
      PubSub.unsubscribe(@daemon, @uri)
      PubSub.publish(@daemon, @uri, data)
      assert_nil received
    end
    
  end

  simulation_context 'PubSub with three permanently connected nodes' do

    uri  = "http://example.com/feed/"

    prepare do
      g = Sim::Graph.new
      g.edge :sub1 => :source
      g.edge :sub2 => :source
      g.edge :sub2 => :nonsub
      sim.events = g.events
      sim.nodes.router :spraywait, :initial_copycount => 1, :cacheSubscriptions => true

      data = "test data"
      sim.node(:source).register("dtn:internet-gw/") {}
      sim.at(1)  {PubSub.subscribe(sim.node(:sub1), uri) {}}
      sim.at(2)  {PubSub.publish(sim.node(:source), uri, data)}
      sim.at(3)  {PubSub.subscribe(sim.node(:sub2), uri) {}}
      sim.at(5)  {PubSub.publish(sim.node(:source), uri, data + "update")}
      sim.at(10) {PubSub.unsubscribe(sim.node(:sub2), uri) {}}
      sim.at(12) {PubSub.publish(sim.node(:source), uri, data + "update2")}
    end

    should 'deliver published content to a subscriber' do
      assert traffic_model.contentItem(uri).delivered?(:sub2)
    end

    should 'not deliver published content to non-subscribing nodes' do
      assert(!traffic_model.contentItem(uri).delivered?(:nonsub))
    end

    should 'deliver published content to previously existing subscribers' do
      assert traffic_model.contentItem(uri).delivered?(:sub1)
    end
    
    should 'deliver updated of published content to a subscriber' do
      assert traffic_model.contentItem(uri).delivered?(:sub1, nil, :revision=>0)
      assert traffic_model.contentItem(uri).delivered?(:sub1, nil, :revision=>1)
      assert traffic_model.contentItem(uri).delivered?(:sub2, nil, :revision=>0)
      assert traffic_model.contentItem(uri).delivered?(:sub2, nil, :revision=>1)
    end

    should 'not deliver updates after unsubscribing' do
      assert traffic_model.contentItem(uri).delivered?(:sub1, nil, :revision=>2)
      assert(!traffic_model.contentItem(uri).delivered?(:sub2,nil,:revision=>2))
    end

    should 'signal subscriptions only once' do
      assert_equal 5, traffic_model.signalingBundles.length
    end
    
  end

  simulation_context 'Two intermittendly connected nodes' do

    uri1  = "http://example.com/feed1/"
    uri2  = "http://example.com/feed2/"
    
    prepare do
      g = Sim::Graph.new
      g.edge :sub1 => :source, :start => 5,  :end => 10
      g.edge :sub1 => :source, :start => 15, :end => 20
      sim.events = g.events
      sim.nodes.router :spraywait, :initial_copycount => 1, :cacheSubscriptions => true

      data = "test data"
      sim.node(:source).register("dtn:internet-gw/") {}
      sim.at(1) do
        PubSub.subscribe(sim.node(:sub1), uri1) {}
        PubSub.subscribe(sim.node(:sub1), uri2) {}
        false
      end
      sim.at(2)  {PubSub.publish(sim.node(:source), uri1, data); false}
      sim.at(11) {PubSub.publish(sim.node(:source), uri2, data+"update");false}
      sim.at(13) {PubSub.delete(sim.node(:source), uri2); false}
    end

    should 'deliver subscribed content when connectivity is available' do
      assert traffic_model.contentItem(uri1).delivered?(:sub1, nil)
    end
    
    should 'not deliver content that was deleted' do
      assert(!traffic_model.contentItem(uri2).delivered?(:sub1, nil))
    end

    should 'not send the same revision twice' do
      assert_equal [1, 0], traffic_model.transmissionsPerContentItem
    end

  end

  simulation_context 'PubSub without subscription caching' do

    uri  = "http://example.com/feed/"

    prepare do
      g = Sim::Graph.new
      g.edge :sub1 => :source
      g.edge :sub2 => :source, :end => 30
      sim.events = g.events
      sim.nodes.router :spraywait, :initial_copycount => 1, :cacheSubscriptions => false, :pollInterval => 10

      data = "test data"
      sim.node(:source).register("dtn:internet-gw/") {}
      sim.at(1)  {PubSub.subscribe(sim.node(:sub1), uri) {}; false}
      sim.at(2)  {PubSub.publish(sim.node(:source), uri, data); false}
      sim.at(3)  {PubSub.subscribe(sim.node(:sub2), uri) {}; false}
      sim.at(12) {PubSub.publish(sim.node(:source), uri, data + "update2"); false}
    end

    should 'deliver the subscribed content' do
      assert(traffic_model.contentItem(uri).delivered?(:sub1,nil,:revision=>0))
      assert(traffic_model.contentItem(uri).delivered?(:sub1,nil,:revision=>1))
      assert(traffic_model.contentItem(uri).delivered?(:sub2,nil,:revision=>0))
      assert(traffic_model.contentItem(uri).delivered?(:sub2,nil,:revision=>1))
    end

    should 'incur signaling traffic' do
      assert_equal 6, traffic_model.signalingBundles.length
    end

  end

  simulation_context 'PubSub with subscription caching' do

    uri  = "http://example.com/feed/"

    prepare do
      g = Sim::Graph.new
      g.edge :sub1 => :source
      g.edge :sub2 => :source, :end => 30
      sim.events = g.events
      sim.nodes.router :spraywait, :initial_copycount => 1, :cacheSubscriptions => true, :pollInterval => 10

      data = "test data"
      sim.node(:source).register("dtn:internet-gw/") {}
      sim.at(1)  {PubSub.subscribe(sim.node(:sub1), uri) {}; false}
      sim.at(2)  {PubSub.publish(sim.node(:source), uri, data); false}
      sim.at(3)  {PubSub.subscribe(sim.node(:sub2), uri) {}; false}
      sim.at(12) {PubSub.publish(sim.node(:source), uri, data + "update2"); false}
    end

    should 'deliver the subscribed content' do
      assert(traffic_model.contentItem(uri).delivered?(:sub1,nil,:revision=>0))
      assert(traffic_model.contentItem(uri).delivered?(:sub1,nil,:revision=>1))
      assert(traffic_model.contentItem(uri).delivered?(:sub2,nil,:revision=>0))
      assert(traffic_model.contentItem(uri).delivered?(:sub2,nil,:revision=>1))
    end

    should 'incur signaling traffic' do
      assert_equal 4, traffic_model.signalingBundles.length
    end

  end
  
end

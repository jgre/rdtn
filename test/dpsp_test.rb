$:.unshift File.join(File.dirname(__FILE__), "..", "lib")
$:.unshift File.join(File.dirname(__FILE__), '../sim/maidenvoyage')

require "test/unit"
require 'rubygems'
require 'shoulda'
require "dpsp"
require "daemon"
require 'maidenvoyage'
require 'graph'

module TestDPSP
  class MockLink < Link
    attr_accessor :remoteEid, :bundle

    def initialize(config, evDis, eid)
      super(config, evDis)
      @bundles = []
      @remoteEid = eid
      @evDis.dispatch(:linkOpen, self)
    end

    def sendBundle(bundle)
      @bundle = bundle
      @bundles.push(bundle)
    end

    def close
    end

    def received?(bundle)
      @bundles.any? {|b| b.to_s == bundle.to_s}
    end

  end
end

class TestDPSPRouter < Test::Unit::TestCase

  def setup
    @daemon = RdtnDaemon::Daemon.new("dtn://receiver.dtn/")
    @store  = @daemon.config.store
    @router = @daemon.router(:dpsp)
  end

  #should 'exchange a subscription bundle, when a link is established' do
  #  eid  = "dtn://peer.dtn/"
  #  link = TestDPSP::MockLink.new(@daemon.config, @daemon.evDis, eid)
  #  assert_not_nil link.bundle
  #end

  #def fakeSubBundle(link)
  #  subSet = SubscriptionSet.new(@daemon.config, @daemon.evDis)
  #  Bundling::Bundle.new(YAML.dump(subSet), 'dtn:subscribe/', eid,
  #      		 :incomingLink => link)
  #end

  #should 'not forward incoming subscription bundles' do
  #  eid   = "dtn://peer.dtn/"
  #  link1 = TestDPSP::MockLink.new(@daemon.config, @daemon.evDis, eid)
  #  link2 = TestDPSP::MockLink.new(@daemon.config, @daemon.evDis,
  #                                 'dtn://thirdparty/')
  #  @daemon.evDis.dispatch(:bundleToForward, fakeSubBundle(link1))
  #  assert !link1.received?(subBundle)
  #  assert !link2.received?(subBundle)
  #end

  #should 'not forward stored subscription bundles' do
  #  eid   = "dtn://peer.dtn/"
  #  link1 = TestDPSP::MockLink.new(@daemon.config, @daemon.evDis, eid)
  #  subBundle = fakeSubBundle(link1)
  #  @daemon.evDis.dispatch(:bundleToForward, subBundle)
  #  @store.storeBundle(subBundle)

  #  link2 = TestDPSP::MockLink.new(@daemon.config, @daemon.evDis,
  #                                 'dtn://thirdparty/')
  #  # Fake the reception of a subscription bundle from the new neighbor
  #  @daemon.evDis.dispatch(:bundleToForward, fakeSubBundle(link))
  #  assert !link1.received?(subBundle)
  #  assert !link2.received?(subBundle)
  #end

  #should 'not forward bundles before a subscription bundle has been received' do
  #  eid    = "dtn://peer.dtn/"
  #  link   = TestDPSP::MockLink.new(@daemon.config, @daemon.evDis, eid)
  #  bundle = Bundling::Bundle.new('test', 'dtn://test/')
  #  @daemon.sendBundle(bundle)
  #  assert !link.received?(bundle)
  #end

  #context 'When bundles are stored, the DPSP router' do

  #  setup do
  #    @bundles = (0..10).map do |i|
  #      Bundling::Bundle.new("test#{i}", 'dtn://someoneelse')
  #    end
  #    @bundles.each {|b| @store.storeBundle(b)}
  #  end

  #  should 'send all bundles to new contacts' do
  #    eid  = "dtn://peer.dtn/"
  #    link = TestDPSP::MockLink.new(@daemon.config, @daemon.evDis, eid)
  #    # Fake the reception of a subscription bundle from the new neighbor
  #    @daemon.evDis.dispatch(:bundleToForward, fakeSubBundle(link))
  #    @bundles.each {|b| assert link.received?(b)}
  #  end

  #end

  #context 'When contacts are established, the DPSP router' do

  #  setup do
  #    @links = (0..10).map do |i|
  #      eid  = "dtn://peer#{i}.dtn/"
  #      l = TestDPSP::MockLink.new(@daemon.config, @daemon.evDis, eid)
  #      # Fake the reception of a subscription bundle from the new neighbor
  #      @daemon.evDis.dispatch(:bundleToForward, fakeSubBundle(l))
  #      l
  #    end
  #  end

  #  should 'send incoming bundles to all existing links' do
  #    bundle = Bundling::Bundle.new('test', 'dtn://someoneelse.dtn/')
  #    @daemon.sendBundle(bundle)

  #    @links.each {|link| assert link.received?(bundle)}
  #  end

  #end

  #context 'With local registrations, the DPSP router' do

  #  setup do
  #    @rec = nil
  #    @daemon.register {|b| @rec = b}
  #  end

  #  should 'deliver bundles to local registrations' do
  #    bundle = Bundling::Bundle.new('test', 'dtn://receiver.dtn/')
  #    @daemon.sendBundle(bundle)
  #    assert @rec
  #    assert_equal bundle, @rec
  #  end
  #  
  #  should 'not deliver bundle to the wrong local registrations' do
  #    bundle = Bundling::Bundle.new('test', 'dtn://someoneelse.dtn/')
  #    @daemon.sendBundle(bundle)
  #    assert_nil @rec
  #  end

  #  should 'continue flooding, when the bundle has a multicast destination' do
  #    bundle = Bundling::Bundle.new('test', 'dtn://receiver.dtn/', nil,
  #                                 :multicast => true)
  #    @daemon.sendBundle(bundle)

  #    eid = 'dtn://peer'
  #    l = TestDPSP::MockLink.new(@daemon.config, @daemon.evDis, eid)
  #    # Fake the reception of a subscription bundle from the new neighbor
  #    @daemon.evDis.dispatch(:bundleToForward, fakeSubBundle(l))
  #    assert l.received?(bundle)
  #  end

  #  should 'stop flooding when a singleton endpoint has been reached' do
  #    bundle = Bundling::Bundle.new('test', 'dtn://receiver.dtn/')
  #    @daemon.sendBundle(bundle)

  #    l = TestDPSP::MockLink.new(@daemon.config,@daemon.evDis,'dtn://peer')
  #    assert !l.received?(bundle)
  #  end

  #  should 'deliver stored bundles when local registration are added' do
  #    bundle = Bundling::Bundle.new('test', 'dtn://someoneelse.dtn/')
  #    @daemon.sendBundle(bundle)

  #    assert_nil @rec
  #    @daemon.register('dtn://someoneelse.dtn/') {|b| @rec = b}
  #    assert @rec
  #    assert_equal bundle, @rec
  #  end

  #  should 'not flood stored bundles to new local registrations' do
  #    bundle = Bundling::Bundle.new('test', 'dtn://someoneelse.dtn/')
  #    @daemon.sendBundle(bundle)

  #    assert_nil @rec
  #    @daemon.register('dtn://thewrongplace.dtn/') {|b| @rec = b}
  #    assert_nil @rec
  #  end

  #end

  #should 'create a subscription for all local registrations' do
  #  uri = 'dtn://channel1'
  #  @daemon.register(uri) {}
  #  assert @router.subSet.subscribed?(uri)
  #end

  #should 'unsubscribe when a local registration ends' do
  #  uri = 'dtn://channel1'
  #  @daemon.register(uri)   {}
  #  @daemon.unregister(uri)
  #  assert(!@router.subSet.subscribed?(uri))
  #end

  #should 'generate a subscription bundle' do
  #  uri  = 'dtn://channel1/'
  #  @daemon.register(uri)   {}

  #  dump   = YAML.dump @router.subSet
  #  bundle = @router.subscriptionBundle
  #  assert_equal dump, bundle.payload
  #end

  #should 'allow the bundle class to recognize subscribe bundles' do
  #  assert @router.subscriptionBundle.isSubscriptionBundle?
  #  assert !(Bundling::Bundle.new.isSubscriptionBundle?)
  #end

  simulation_context 'DPSP with popularity prio for two connected nodes' do

    prepare do
      g = Sim::Graph.new
      g.edge 1 => 2, :start => 1, :end => 4
      g.edge 1 => 2, :start => 10, :end => 15
      sim.events = g.events

      sim.nodes.router(:dpsp, :prios => [:popularity])

      @channel1 = 'dtn://channel1/'
      @channel2 = 'dtn://channel2/'
      sim.at(5) do
	@b1=sim.node(1).sendDataTo 'test'*1000,@channel1,nil,:multicast => true
	false
      end
      sim.at(6) do
	@b2=sim.node(1).sendDataTo 'test'*1000,@channel2,nil,:multicast => true
	false
      end
      sim.at(2) do
	sim.node(2).register(@channel2) {}
	false
      end
    end

    should 'transmit one bundle' do
      assert_equal 2, traffic_model.numberOfBundles
      assert_equal 1, traffic_model.numberOfExpectedBundles
      assert_equal 3, traffic_model.numberOfTransmissions
    end

    should 'prioritize the subscribed bundle' do
      assert(traffic_model.regularBundles.find{|b| b.dest == 'dtn://channel1/'}.incidents[2].empty?)
      assert(!traffic_model.regularBundles.find{|b| b.dest == 'dtn://channel2/'}.incidents[2].empty?)
    end

  end
  
  simulation_context 'DPSP with known subscription filter' do

    prepare do
      g = Sim::Graph.new
      g.edge 1 => 2, :start => 1, :end => 10
      sim.events = g.events

      sim.nodes.router(:dpsp, :filters => [:knownSubscription?])

      @channel1 = 'dtn://channel1/'
      @channel2 = 'dtn://channel2/'
      sim.at(0) do
	sim.node(2).register(@channel2) {}
	false
      end
      sim.at(2) do
	sim.node(1).sendDataTo 'test'*1000,@channel1,nil,:multicast => true
	sim.node(1).sendDataTo 'test'*1000,@channel2,nil,:multicast => true
	false
      end
    end

    should 'filter the queue' do
      assert_equal 2, traffic_model.numberOfBundles
      assert_equal 2, traffic_model.numberOfTransmissions
      assert_equal 1, traffic_model.deliveryRatio
    end
    
  end

  simulation_context 'DPSP with hop count filter' do

    prepare do
      g = Sim::Graph.new
      g.edge 1 => 2, :start => 1, :end => 10
      g.edge 2 => 3, :start => 1, :end => 10
      sim.events = g.events

      sim.nodes.router(:dpsp, :filters => [:exceedsHopCountLimit?],
		        :hopCountLimit => 1)

      @channel1 = 'dtn://channel1/'
      @channel2 = 'dtn://channel2/'
      sim.at(0) do
	sim.node(3).register(@channel1) {}
	false
      end
      sim.at(2) do
	bundle = Bundling::Bundle.new 'test',@channel1,nil,:multicast => true
	block  = HopCountBlock.new(bundle)
	bundle.addBlock(block)
	sim.node(1).sendBundle bundle
	false
      end
    end

    should 'filter the queue' do
      assert_equal 1, traffic_model.numberOfBundles
      assert_equal 3, traffic_model.numberOfTransmissions
      assert_equal 1, traffic_model.numberOfExpectedBundles
      assert_equal 0, traffic_model.deliveryRatio
    end

  end

  simulation_context 'DPSP with popularity prio when bundles are sent over an existing contact' do

    prepare do
      g = Sim::Graph.new
      g.edge 1 => 2, :start => 1, :end => 10
      sim.events = g.events

      sim.nodes.router(:dpsp, :prios => [:popularity])

      @channel1 = 'dtn://channel1/'
      @channel2 = 'dtn://channel2/'
      sim.at(0) do
	sim.node(2).register(@channel2) {}
	false
      end
      sim.at(2) do
	sim.node(1).sendDataTo 'test'*1000,@channel2,nil,:multicast => true
	false
      end
      sim.at(3) do
	sim.node(1).sendDataTo 'test'*1000,@channel1,nil,:multicast => true
	false
      end
      sim.at(4) do
	sim.node(1).sendDataTo 'test'*1000,@channel2,nil,:multicast => true
	false
      end
    end

    should 'priorize the bundles in the queue to deliver the subscribed bundles' do
      assert_equal 3, traffic_model.numberOfTransmissions
      assert_equal 3, traffic_model.numberOfBundles
      assert_equal 1, traffic_model.deliveryRatio
    end

  end

  simulation_context 'DPSP with hop count prio when bundles are sent over an existing contact' do

    prepare do
      g = Sim::Graph.new
      g.edge 1 => 2, :start => 1, :end => 10
      g.edge 3 => 2, :start => 1, :end => 10
      g.edge 4 => 3, :start => 1, :end => 10
      g.edge 2 => 5, :start => 10, :end => 13
      sim.events = g.events

      sim.nodes.router(:dpsp, :prios => [:hopCount])

      @channel1 = 'dtn://channel1/'
      sim.at(0) do
	sim.node(5).register(@channel1) {}
	false
      end
      sim.at(2) do
	bundle = Bundling::Bundle.new 'a'*2048,@channel1,nil,:multicast => true
	block  = HopCountBlock.new(bundle)
	bundle.addBlock(block)
	sim.node(4).sendBundle bundle
	false
      end
      sim.at(5) do
	bundle = Bundling::Bundle.new 'a'*2048,@channel1,nil,:multicast => true
	block  = HopCountBlock.new(bundle)
	bundle.addBlock(block)
	sim.node(1).sendBundle bundle
	false
      end
    end

    should 'priorize the bundles with fewer hops' do
      assert_equal 7,   traffic_model.numberOfTransmissions
      assert_equal 2,   traffic_model.numberOfBundles
      assert_equal 0.5, traffic_model.deliveryRatio
      assert(!traffic_model.regularBundles.find{|b| b.src == 1}.incidents[5].empty?)
      assert(traffic_model.regularBundles.find{|b| b.src == 4}.incidents[5].empty?)
    end

  end

  simulation_context 'DPSP with short delay prio when bundles are sent over an existing contact' do

    prepare do
      g = Sim::Graph.new
      g.edge 1 => 2, :start => 1, :end => 10
      g.edge 2 => 3, :start => 10, :end => 13
      sim.events = g.events

      sim.nodes.router(:dpsp, :prios => [:shortDelay])

      @channel1 = 'dtn://channel1/'
      @channel2 = 'dtn://channel2/'
      sim.at(0) do
	sim.node(3).register(@channel1) {}
	false
      end
      sim.at(2) do
	sim.node(1).sendDataTo 'a'*2048,@channel2,nil,:multicast => true
	false
      end
      sim.at(5) do
	sim.node(1).sendDataTo 'a'*2048,@channel1,nil,:multicast => true
	false
      end
    end

    should 'priorize newer bundles' do
      assert_equal 2, traffic_model.numberOfBundles
      assert_equal 1, traffic_model.deliveryRatio
    end

  end

  simulation_context 'DPSP with proximity prio' do

    prepare do
      g = Sim::Graph.new
      g.edge 1 => 2, :start => 1
      g.edge 2 => 3, :start => 1,  :end => 3
      g.edge 2 => 3, :start => 10, :end => 13
      g.edge 3 => 4, :start => 1
      g.edge 4 => 5, :start => 1
      g.edge 2 => 5, :start => 1,  :end => 3
      g.edge 2 => 5, :start => 10, :end => 13
      g.edge 5 => 6, :start => 1
      sim.events = g.events

      sim.nodes.router(:dpsp, :prios => [:proximity], :subsRange => 5)

      @channel1 = 'dtn://channel1/'
      @channel2 = 'dtn://channel2/'
      sim.at(0) do
	sim.node(3).register(@channel1) {}
	sim.node(6).register(@channel2) {}
	false
      end
      sim.at(5) do
	sim.node(1).sendDataTo 'a'*2048,@channel1,nil,:multicast => true
	sim.node(1).sendDataTo 'a'*2048,@channel2,nil,:multicast => true
	false
      end
    end

    should 'priorize shorter routes based on incoming subscriptions' do
      assert_equal 2, traffic_model.numberOfBundles
      assert_equal 1, traffic_model.deliveryRatio
    end

  end

end


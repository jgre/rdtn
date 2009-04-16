$:.unshift File.join(File.dirname(__FILE__), "..", "lib")
$:.unshift File.join(File.dirname(__FILE__), '../sim/maidenvoyage')

require "test/unit"
require 'rubygems'
require 'shoulda'
require "ccndpsp"
require "daemon"
require 'maidenvoyage'
require 'graph'
require 'pubsub'

class TestCCNDPSPRouter < Test::Unit::TestCase

  def setup
    @daemon = RdtnDaemon::Daemon.new("dtn://receiver.dtn/")
    @store  = @daemon.config.store
    @router = @daemon.router(:dpsp)
  end

  simulation_context 'DPSP with popularity prio for two connected nodes' do

    prepare do
      g = Sim::Graph.new
      g.edge 1 => 2, :start => 1, :end => 4
      g.edge 1 => 2, :start => 10, :end => 15
      sim.events = g.events

      sim.nodes.router(:ccndpsp, :prios => [:popularity],
                       :cacheSubscriptions => true)
      
      @channel1 = 'dtn://channel1/'
      @channel2 = 'dtn://channel2/'
      sim.node(1).register("dtn:internet-gw/") {}
      sim.at(5) do
        PubSub.publish sim.node(1), @channel1, 'test'*1000
	false
      end
      sim.at(6) do
        PubSub.publish sim.node(1), @channel2, 'test'*1000
	false
      end
      sim.at(2) do
        PubSub.subscribe(sim.node(2), @channel2) {}
	false
      end
    end

    should 'transmit one bundle' do
      assert_equal 1, traffic_model.expectedContentItemCount
    end

    should 'prioritize the subscribed bundle' do
      assert(!traffic_model.contentItem('dtn://channel1/').delivered?(2))
      assert(traffic_model.contentItem('dtn://channel2/').delivered?(2))
    end

  end
  
  simulation_context 'DPSP with known subscription filter' do

    prepare do
      g = Sim::Graph.new
      g.edge 1 => 2, :start => 1, :end => 10
      sim.events = g.events

      sim.nodes.router(:ccndpsp, :filters => [:knownSubscription?],
                       :cacheSubscriptions => true)
      sim.node(1).register("dtn:internet-gw/") {}

      @channel1 = 'dtn://channel1/'
      @channel2 = 'dtn://channel2/'
      sim.at(0) do
        PubSub.subscribe(sim.node(2), @channel2) {}
	false
      end
      sim.at(2) do
        PubSub.publish(sim.node(1), @channel1, 'test'*1000)
        PubSub.publish(sim.node(1), @channel2, 'test'*1000)
	false
      end
    end

    should 'filter the queue' do
      assert_equal 2, traffic_model.contentItemCount
      assert_equal 1, traffic_model.contentItemDeliveryRatio
    end
    
  end

  simulation_context 'DPSP with popularity prio when bundles are sent over an existing contact' do

    prepare do
      g = Sim::Graph.new
      g.edge 1 => 2, :start => 1, :end => 10
      sim.events = g.events

      sim.nodes.router(:dpsp, :prios => [:popularity],
                       :cacheSubscriptions => true)

      @channel1 = 'dtn://channel1/'
      @channel2 = 'dtn://channel2/'
      sim.node(1).register("dtn:internet-gw/") {}
      sim.at(0) do
        PubSub.subscribe(sim.node(2), @channel2) {}
        false
      end
      sim.at(2) do
        PubSub.publish(sim.node(1), @channel2, 'test'*1000)
        false
      end
      sim.at(3) do
        PubSub.publish(sim.node(1), @channel1, 'test'*1000)
	false
      end
      sim.at(4) do
        PubSub.publish(sim.node(1), @channel2, 'test'*1000)
	false
      end
    end

    should 'priorize the bundles in the queue to deliver the subscribed bundles' do
      #assert_equal 3, traffic_model.numberOfTransmissions
      assert_equal 3, traffic_model.numberOfBundles
      assert_equal 1, traffic_model.contentItemDeliveryRatio
    end

  end

  simulation_context 'DPSP with short delay prio when bundles are sent over an existing contact' do

    prepare do
      g = Sim::Graph.new
      g.edge 1 => 2, :start => 1, :end => 10
      g.edge 2 => 3, :start => 10, :end => 13
      sim.events = g.events

      sim.nodes.router(:dpsp, :prios => [:shortDelay],
                       :cacheSubscriptions => true)
      @channel1 = 'dtn://channel1/'
      @channel2 = 'dtn://channel2/'
      sim.node(1).register("dtn:internet-gw/") {}
      sim.at(0) do
        PubSub.subscribe(sim.node(3), @channel1) {}
	false
      end
      sim.at(2) do
        PubSub.publish(sim.node(1), @channel2, 'a'*2048)
	false
      end
      sim.at(5) do
        PubSub.publish(sim.node(1), @channel1, 'a'*2048)
	false
      end
    end

    should 'priorize newer bundles' do
      assert_equal 2, traffic_model.contentItemCount
      assert_equal 1, traffic_model.contentItemDeliveryRatio
    end

  end

end

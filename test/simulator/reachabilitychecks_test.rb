$:.unshift File.join(File.dirname(__FILE__), '../../sim/stats')
$:.unshift File.join(File.dirname(__FILE__), '../../sim')

require 'rubygems'
require 'test/unit'
require 'shoulda'
require 'trafficmodel'
require 'networkmodel'
require 'logentry'

class ReachabilityCheckTest < Test::Unit::TestCase

  context 'TrafficModel' do

    setup do
      @t0   = Time.now
      @b1  = Bundling::Bundle.new('test', 'dtn://group/', 'dtn://kasuari1',
				  :multicast => true)
      @log = [
	Sim::LogEntry.new(0, :bundleCreated, 1, nil, :bundle => @b1),
	Sim::LogEntry.new(0, :registered, 2, nil, :eid => 'dtn://group/'),
	Sim::LogEntry.new(0, :registered, 3, nil, :eid => 'dtn://group/'),
	Sim::LogEntry.new(0, :registered, 4, nil, :eid=>'dtn://group/'),
	Sim::LogEntry.new(1, :bundleForwarded, 1, 2, :bundle => @b1),
	Sim::LogEntry.new(1, :bundleForwarded, 1, 3, :bundle => @b1),
      ]
      @tm  = TrafficModel.new(@t0, @log)

      @events = Sim::EventQueue.new
      @events.addEvent(0, 1, 2, :simConnection)
      @events.addEvent(1, 1, 3, :simConnection)
      @net = NetworkModel.new(@events)
    end

    should 'count expected bundles for unreachable nodes when reachability checks are disabled' do
      assert_equal 3, @tm.numberOfExpectedBundles
    end

    should 'not count expected bundles for unreachable nodes when reachability checks are available' do
      assert_equal 2, @tm.numberOfExpectedBundles(@net)
    end

    should 'not count expected bundles for node that cannot be reached before the bundle expires' do
      @events.addEvent(3601, 1, 4, :simConnection)
      @net = NetworkModel.new(@events)
      assert_equal 2, @tm.numberOfExpectedBundles(@net)
    end

    should 'count expected bundles that can arrive during the lifetime of the bundle' do
      b2  = Bundling::Bundle.new('testtest', 'dtn://group/', 'dtn://kasuari1',
				 :multicast => true)
      b2.creationTimestamp += 3601
      @events.addEvent(3610, 1, 4, :simConnection)
      @net = NetworkModel.new(@events)
      @log << Sim::LogEntry.new(3601, :bundleCreated, 1, nil, :bundle => b2)
      @tm  = TrafficModel.new(@t0, @log)
      assert_equal 5, @tm.numberOfExpectedBundles(@net)
    end

    should 'not count bundles for nodes that cannot be reached before the registration expires' do
      @log << Sim::LogEntry.new(10, :unregistered, 4, nil, :eid=>'dtn://group/')
      @events.addEvent(11, 1, 4, :simConnection)
      @tm  = TrafficModel.new(@t0, @log)
      @net = NetworkModel.new(@events)
      assert_equal 2, @tm.numberOfExpectedBundles(@net)
    end

    should 'base the calculation of the delivery ratio on expected bundles accounting for reachability' do
      assert_equal 1, @tm.deliveryRatio(@net)
    end

  end

end

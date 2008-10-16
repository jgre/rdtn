$:.unshift File.join(File.dirname(__FILE__), '../../sim/stats')
$:.unshift File.join(File.dirname(__FILE__), '../../sim')

require 'rubygems'
require 'test/unit'
require 'shoulda'
require 'trafficmodel'
require 'logentry'

class TrafficModelTest < Test::Unit::TestCase

  context 'In a unicast scenario, TrafficModel' do

    setup do
      t0   = Time.now
      @b1  = Bundling::Bundle.new('test', 'dtn://kasuari2/', 'dtn://kasuari1')
      @b2  = Bundling::Bundle.new('test', 'dtn://kasuari3/', 'dtn://kasuari1')
      @b3  = Bundling::Bundle.new('test', 'dtn://kasuari3/', 'dtn://kasuari1')
      @log = [
        Sim::LogEntry.new(0, :bundleCreated, 1, nil, :bundle => @b1),
        Sim::LogEntry.new(0, :bundleCreated, 1, nil, :bundle => @b2),
        Sim::LogEntry.new(0, :bundleCreated, 1, nil, :bundle => @b3),
        Sim::LogEntry.new(1, :bundleForwarded, 1, 2, :bundle => @b1),
        Sim::LogEntry.new(2, :bundleForwarded, 1, 2, :bundle => @b1), # duplicate
        Sim::LogEntry.new(1, :bundleForwarded, 1, 3, :bundle => @b1),
        Sim::LogEntry.new(9, :bundleForwarded, 1, 3, :bundle => @b2),
        Sim::LogEntry.new(9, :bundleForwarded, 1, 2, :bundle => @b3), # the wrong one
      ]
      @tm  = TrafficModel.new(t0, @log)
    end

    should 'count the bundles' do
      assert_equal 3, @tm.numberOfBundles
    end

    should 'sum the delays of all delivered bundles' do
      assert_equal 10, @tm.totalDelay
    end

    should 'calculate the average delay of all delivered bundles' do
      assert_equal 5, @tm.averageDelay
    end

    should 'count replicas' do
      assert_equal 4, @tm.numberOfReplicas
    end

    should 'count replicas for individual bundles' do
      assert_equal 2, @tm.numberOfReplicas(@b1)
    end

    should 'calulate the number of replicas per bundle' do
      assert_equal 4.0/3, @tm.replicasPerBundle
    end

    should 'count the delivered bundles' do
      assert_equal 2, @tm.numberOfDeliveredBundles
    end

    should 'count the transmissions' do
      assert_equal 5, @tm.numberOfTransmissions
    end

    should 'calculate the transmissions per bundle' do
      assert_equal 5.0/3, @tm.transmissionsPerBundle
    end

    should 'calculate the delivery ratio' do
      assert_equal 2.0/3, @tm.deliveryRatio
    end

    should_eventually 'calculate the replicas per delivered bundle' do
      assert_equal 4/2, @tm.replicasPerDeliveredBundle
    end

    should_eventually 'calculate the number of transmissions per delivered bundle' do
      assert_equal 4/2.0, @tm.transmissionsPerDeliveredBundle
    end

  end

  context 'In a multicast scenario, TrafficModel' do

    setup do
      @t0   = Time.now
      @b1  = Bundling::Bundle.new('test', 'dtn://group/', 'dtn://kasuari1',
                                 :multicast => true)
      @log = [
        Sim::LogEntry.new(0, :bundleCreated, 1, nil, :bundle => @b1),
        Sim::LogEntry.new(0, :registered, 2, nil, :eid => 'dtn://group/'),
        Sim::LogEntry.new(0, :registered, 3, nil, :eid => 'dtn://group/'),
        Sim::LogEntry.new(1, :bundleForwarded, 1, 2, :bundle => @b1),
        Sim::LogEntry.new(1, :bundleForwarded, 1, 3, :bundle => @b1),
      ]
      @tm  = TrafficModel.new(@t0, @log)
    end

    should 'count expected bundles' do
      assert_equal 2, @tm.numberOfExpectedBundles
    end

    should 'not count expected bundles that expire before the registration is created' do
      @log << Sim::LogEntry.new(3601, :registered, 4, nil, :eid=>'dtn://group/')
      @tm  = TrafficModel.new(@t0, @log)
      assert_equal 2, @tm.numberOfExpectedBundles
    end

    should 'not count expected bundles that are created after the registration expires' do
      b2  = Bundling::Bundle.new('testtest', 'dtn://group/', 'dtn://kasuari1',
				 :multicast => true)
      b2.creationTimestamp += 11
      @log << Sim::LogEntry.new(10, :unregistered, 3, nil, :eid=>'dtn://group/')
      @log << Sim::LogEntry.new(11, :bundleCreated, 1, nil, :bundle => b2)
      @tm  = TrafficModel.new(@t0, @log)
      assert_equal 3, @tm.numberOfExpectedBundles
    end

    should 'count delivered bundles' do
      assert_equal 2, @tm.numberOfDeliveredBundles
    end

    should 'not count delivered bundles that expire before the registration is created' do
      @log << Sim::LogEntry.new(3601, :registered, 4, nil, :eid=>'dtn://group/')
      @log << Sim::LogEntry.new(1, :bundleForwarded, 1, 4, :bundle => @b1)
      @tm  = TrafficModel.new(@t0, @log)
      assert_equal 2, @tm.numberOfDeliveredBundles
    end

    should 'not count delivered bundles that are created after the registration expires' do
      b2  = Bundling::Bundle.new('testtest', 'dtn://group/', 'dtn://kasuari1',
				 :multicast => true)
      b2.creationTimestamp += 11
      @log << Sim::LogEntry.new(10, :unregistered, 3, nil, :eid=>'dtn://group/')
      @log << Sim::LogEntry.new(11, :bundleCreated, 1, nil, :bundle => b2)
      @log << Sim::LogEntry.new(11, :bundleForwarded, 1, 3, :bundle => b2)
      @tm  = TrafficModel.new(@t0, @log)
      assert_equal 2, @tm.numberOfDeliveredBundles
    end

    should 'calculate the delivery ratio based on registrations' do
      assert_equal 1, @tm.deliveryRatio
    end

    should 'calculate the average delay of all delivered bundles' do
      assert_equal 1, @tm.averageDelay
    end

  end

  context 'When signaling bundles are logged, TrafficModel' do

    setup do
      t0   = Time.now
      @b1  = Bundling::Bundle.new('test', 'dtn://kasuari2/', 'dtn://kasuari1')
      @vacc = Vaccination.new(@b1).vaccinationBundle
      @log = [
        Sim::LogEntry.new(0, :bundleCreated, 1, nil, :bundle => @b1),
        Sim::LogEntry.new(0, :bundleCreated, 2, nil, :bundle => @vacc),
        Sim::LogEntry.new(1, :bundleForwarded, 1, 2, :bundle => @b1),
        Sim::LogEntry.new(2, :bundleForwarded, 2, 1, :bundle => @vacc),
      ]
      @tm  = TrafficModel.new(t0, @log)
    end

    should 'only count non-signaling bundles as "normal" bundles' do
      assert_equal 1, @tm.numberOfBundles
    end

    should 'count signaling bundles' do
      assert_equal 1, @tm.numberOfSignalingBundles
    end

    should 'not count vaccination bundles as expected' do
      assert_equal 1, @tm.numberOfExpectedBundles
    end

    should 'not count vaccination bundles as delivered' do
      assert_equal 1, @tm.numberOfDeliveredBundles
    end

    should 'not count vaccination bundles as transmissions' do
      assert_equal 1, @tm.numberOfTransmissions
    end

  end

end

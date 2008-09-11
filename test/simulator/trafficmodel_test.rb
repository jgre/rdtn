$:.unshift File.join(File.dirname(__FILE__), '../../sim/stats')
$:.unshift File.join(File.dirname(__FILE__), '../../sim')

require 'rubygems'
require 'test/unit'
require 'shoulda'
require 'trafficmodel'
require 'logentry'

class TrafficModelTest < Test::Unit::TestCase

  def setup
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

$:.unshift File.join(File.dirname(__FILE__), '../../sim/stats')
$:.unshift File.join(File.dirname(__FILE__), '../../sim')

require 'rubygems'
require 'test/unit'
require 'shoulda'
require 'trafficmodel'
require 'logentry'
require 'ccnblock'

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

    should 'count the volume of transmissions (in bytes)' do
      assert_equal 20, @tm.bytesTransmitted
    end

    should 'calculate the transmissions per bundle' do
      assert_equal 5.0/3, @tm.transmissionsPerBundle
    end

    should 'calculate the delivery ratio' do
      assert_equal 2.0/3, @tm.deliveryRatio
    end

  end

  context 'In a multicast scenario, TrafficModel' do

    setup do
      @t0   = Time.now
      @b1  = Bundling::Bundle.new('test', 'dtn://group/', 'dtn://kasuari1',
                                  :multicast => true)
      @tm = TrafficModel.new(@t0)
      @tm.event(Sim::LogEntry.new(0, :bundleCreated, 1, nil, :bundle => @b1))
      @tm.event(Sim::LogEntry.new(0, :registered, 2, nil, :eid=>'dtn://group/'))
      @tm.event(Sim::LogEntry.new(0, :registered, 3, nil, :eid=>'dtn://group/'))
      @tm.event(Sim::LogEntry.new(1, :bundleForwarded, 1, 2, :bundle => @b1))
      @tm.event(Sim::LogEntry.new(1, :bundleForwarded, 1, 3, :bundle => @b1))
    end

    should 'count expected bundles' do
      assert_equal 2, @tm.numberOfExpectedBundles
    end

    should 'not count expected bundles that expire before the registration is created' do
      @tm.event(Sim::LogEntry.new(3601, :registered,4,nil,:eid=>'dtn://group/'))
      assert_equal 2, @tm.numberOfExpectedBundles
    end

    should 'not count expected bundles that are created after the registration expires' do
      b2  = Bundling::Bundle.new('testtest', 'dtn://group/', 'dtn://kasuari1',
				 :multicast => true)
      b2.creationTimestamp += 11
      @tm.event(Sim::LogEntry.new(10, :unregistered,3,nil,:eid=>'dtn://group/'))
      @tm.event(Sim::LogEntry.new(11, :bundleCreated, 1, nil, :bundle => b2))
      assert_equal 3, @tm.numberOfExpectedBundles
    end

    should 'count delivered bundles' do
      assert_equal 2, @tm.numberOfDeliveredBundles
    end

    should 'not count delivered bundles that expire before the registration is created' do
      @tm.event(Sim::LogEntry.new(3601, :registered,4,nil,:eid=>'dtn://group/'))
      @tm.event(Sim::LogEntry.new(1, :bundleForwarded,1,4,:bundle => @b1))
      assert_equal 2, @tm.numberOfDeliveredBundles
    end

    should 'not count delivered bundles that are created after the registration expires' do
      b2  = Bundling::Bundle.new('testtest', 'dtn://group/', 'dtn://kasuari1',
				 :multicast => true)
      b2.creationTimestamp += 11
      @tm.event(Sim::LogEntry.new(10, :unregistered,3,nil,:eid=>'dtn://group/'))
      @tm.event(Sim::LogEntry.new(11, :bundleCreated, 1, nil, :bundle => b2))
      @tm.event(Sim::LogEntry.new(11, :bundleForwarded, 1, 3, :bundle => b2))
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

    should 'count vaccination bundles as transmissions' do
      assert_equal 2, @tm.numberOfTransmissions
    end

  end

  context 'When storage events are logged, TrafficModel' do

    setup do
      t0   = Time.now
      @b1  = Bundling::Bundle.new('test', 'dtn://kasuari2/', 'dtn://kasuari1')
      @b2  = Bundling::Bundle.new('test', 'dtn://kasuari2/', 'dtn://kasuari1')
      @log = [
        Sim::LogEntry.new(0, :bundleCreated, 1, nil, :bundle => @b1),
        Sim::LogEntry.new(0, :bundleCreated, 1, nil, :bundle => @b2),
        Sim::LogEntry.new(1, :bundleForwarded, 1, 2, :bundle => @b1),
        Sim::LogEntry.new(1, :bundleForwarded, 1, 2, :bundle => @b2),
        Sim::LogEntry.new(1, :bundleStored, 2, nil,  :bundle => @b1),
        Sim::LogEntry.new(1, :bundleStored, 2, nil,  :bundle => @b2),
        Sim::LogEntry.new(100, :bundleRemoved, 2, nil,  :bundle => @b1),
        Sim::LogEntry.new(250, :bundleRemoved, 2, nil,  :bundle => @b2),
      ]
      @tm  = TrafficModel.new(t0, @log)
    end

    should 'have a list of samples of the buffer use' do
      assert_kind_of Array, @tm.bufferUse(10)
      assert_equal 25, @tm.bufferUse(10).length
    end

    should 'list the current size of the buffer for each sampling time' do
      assert_equal [8, 4, 4, 4, 0], @tm.bufferUse(50)
    end

    should 'list the current size of the buffer for each node' do
      @tm.event(Sim::LogEntry.new(0, :bundleStored, 1, nil, :bundle => @b1))
      assert_same_elements [4, 4, 4, 4, 4, 8, 4, 4, 4, 0], @tm.bufferUse(50)
    end

  end

  context 'When transmission errors are logged, TrafficModel' do

    setup do
      t0   = Time.now
      @b1  = Bundling::Bundle.new('test', 'dtn://kasuari2/', 'dtn://kasuari1')
      @sig = Bundling::Bundle.new('test', 'dtn:subscribe/', 'dtn://kasuari1')
      @log = [
        Sim::LogEntry.new(0, :bundleCreated, 1, nil, :bundle => @b1),
        Sim::LogEntry.new(0, :bundleCreated, 1, nil, :bundle => @sig),
        Sim::LogEntry.new(1, :bundleForwarded, 1, 2, :bundle => @b1),
        Sim::LogEntry.new(1, :bundleForwarded, 1, 2, :bundle => @sig),
        Sim::LogEntry.new(1, :transmissionError, 1, 3, :transmitted => 100, :bundle => @b1),
        Sim::LogEntry.new(2, :transmissionError, 1, 3, :transmitted => 100, :bundle => @sig),
        Sim::LogEntry.new(4, :transmissionError, 1, 4, :transmitted => 200, :bundle => @b1),
      ]
      @tm  = TrafficModel.new(t0, @log)
    end

    should 'not include the failed transmissions in the transmission count' do
      assert_equal 2, @tm.numberOfTransmissions
      assert_equal 8, @tm.bytesTransmitted
    end

    should 'count transmission errors' do
      assert_equal 3, @tm.numberOfTransmissionErrors
    end

    should 'count the volume of failed transmissions (in bytes)' do
      assert_equal 400, @tm.failedTransmissionVolume
    end

    should 'optionally ignore signaling bundles when counting transmissions' do
      assert_equal 1, @tm.numberOfTransmissions(:ignoreSignaling => true)
    end

    should 'optionally ignore signaling bundles when counting transmission volueme' do
      assert_equal 4, @tm.bytesTransmitted(:ignoreSignaling => true)
    end

    should 'optionally ignore signaling bundles when counting failed transmissions' do
      assert_equal 2, @tm.numberOfTransmissionErrors(:ignoreSignaling => true)
    end

    should 'optionally ignore signaling bundles when counting the volume of failed transmissions' do
      assert_equal 300, @tm.failedTransmissionVolume(:ignoreSignaling => true)
    end

  end

  context 'With a warmup period' do

    setup do
      t0   = Time.now
      @b1  = Bundling::Bundle.new('test', 'dtn://kasuari2/', 'dtn://kasuari1')
      @b2  = Bundling::Bundle.new('test', 'dtn://kasuari3/', 'dtn://kasuari1')
      @b2.creationTimestamp += 1
      @b3  = Bundling::Bundle.new('test', 'dtn://kasuari3/', 'dtn://kasuari1')
      @b2.creationTimestamp += 10
      @log = [
        Sim::LogEntry.new(0, :bundleCreated, 1, nil, :bundle => @b1),
        Sim::LogEntry.new(1, :bundleCreated, 1, nil, :bundle => @b2),
        Sim::LogEntry.new(10, :bundleCreated, 1, nil, :bundle => @b3),
        Sim::LogEntry.new(1, :bundleForwarded, 1, 2, :bundle => @b1),
        Sim::LogEntry.new(11, :bundleForwarded, 1, 3, :bundle => @b2),
        Sim::LogEntry.new(12, :bundleForwarded, 1, 3, :bundle => @b3),
        Sim::LogEntry.new(1, :transmissionError, 1, 3, :transmitted => 100, :bundle => @b1),
        Sim::LogEntry.new(15, :transmissionError, 1, 3, :transmitted => 2, :bundle => @b1),
      ]
      @tm  = TrafficModel.new(t0, @log)
      @tm.warmup = 10
    end

    should 'count only the bundles after the warmup phase' do
      assert_equal 1, @tm.numberOfBundles
    end

    should 'only expect bundles after the warmup phase' do
      assert_equal 1, @tm.numberOfExpectedBundles
    end

    should 'only count delivered bundles after the warmup phase' do
      assert_equal 1, @tm.numberOfDeliveredBundles
    end

    should 'only list delays after the warmup phase' do
      assert_equal 1, @tm.delays.length
    end

    should 'only count replicas after the warmup phase' do
      assert_equal 1, @tm.numberOfReplicas
      assert_equal 1, @tm.replicasPerBundle
    end

    should 'only count transmissions after the warmup phase' do
      assert_equal 1, @tm.numberOfTransmissions
      assert_equal 1, @tm.transmissionsPerBundle
    end

    should 'only count bytes transmitted after the warmup phase' do
      assert_equal 4, @tm.bytesTransmitted
    end

    should 'only count transmission failures after the warmup phase' do
      assert_equal 1, @tm.numberOfTransmissionErrors
      assert_equal 2, @tm.failedTransmissionVolume
    end

  end

  context 'With CCN' do

    setup do
      t0 = Time.now
      @uri = "http://example.com/feed/"
      @b = Bundling::Bundle.new('test', nil, 'dtn://kasuari1')
      @b.addBlock CCNBlock.new(@b, @uri, :publish, :revision => 0)
      @b.creationTimestamp += 10
      @upd = Bundling::Bundle.new('updated', nil, 'dtn://kasuari1')
      @upd.addBlock CCNBlock.new(@upd, @uri, :publish, :revision => 1)
      @upd.creationTimestamp += 11

      @sub2 = Bundling::Bundle.new(nil, nil, 'dtn://kasuari2')
      @sub2.addBlock CCNBlock.new(@sub2, @uri, :subscribe)
      @sub3 = Bundling::Bundle.new(nil, nil, 'dtn://kasuari3')
      @sub3.addBlock CCNBlock.new(@sub3, @uri, :subscribe)
      @sub4 = Bundling::Bundle.new(nil, nil, 'dtn://kasuari4')
      @sub4.addBlock CCNBlock.new(@sub4, @uri, :subscribe)
      @unsub4 = Bundling::Bundle.new(nil, nil, 'dtn://kasuari4')
      @unsub4.addBlock CCNBlock.new(@unsub4, @uri, :unsubscribe)
      @unsub4.creationTimestamp += 5
      @unsub3 = Bundling::Bundle.new(nil, nil, 'dtn://kasuari3')
      @unsub3.addBlock CCNBlock.new(@unsub3, @uri, :unsubscribe)
      @unsub3.creationTimestamp += 15
      
      @log = [
              Sim::LogEntry.new(10, :bundleCreated, 1, nil, :bundle => @b),
              Sim::LogEntry.new(10, :bundleCreated, 2, nil, :bundle => @sub2),
              Sim::LogEntry.new(10, :bundleCreated, 3, nil, :bundle => @sub3),
              Sim::LogEntry.new(1,  :bundleCreated, 4, nil, :bundle => @sub4),
              Sim::LogEntry.new(5,  :bundleCreated, 4, nil, :bundle => @unsub4),
              Sim::LogEntry.new(15, :bundleCreated, 4, nil, :bundle => @unsub3),
              Sim::LogEntry.new(11, :bundleCreated, 1, nil, :bundle => @upd),
              Sim::LogEntry.new(10, :contentCached, 1, nil, :bundle => @b),
              Sim::LogEntry.new(11, :bundleForwarded, 1, 2, :bundle => @b),
              Sim::LogEntry.new(11, :bundleForwarded, 1, 4, :bundle => @b),
              Sim::LogEntry.new(12, :bundleForwarded, 1, 4, :bundle => @b),
              Sim::LogEntry.new(11, :contentCached,  4, nil, :bundle => @b),
              Sim::LogEntry.new(20, :contentUncached,  4, nil, :bundle => @b),
              Sim::LogEntry.new(19, :bundleForwarded, 1, 2, :bundle => @upd),
      ]
      @tm  = TrafficModel.new(t0, @log)      
    end

    should 'track the content items' do
      assert_equal 1, @tm.contentItemCount
    end

    should 'track which nodes received which content items' do
      assert  @tm.contentItem(@uri).delivered?(2, @tm.subscription(@uri, 2))
      assert(!@tm.contentItem(@uri).delivered?(3, @tm.subscription(@uri, 3)))
      assert(!@tm.contentItem(@uri).delivered?(4, @tm.subscription(@uri, 4)))
    end

    should 'track subscriptions' do
      assert_same_elements [2, 3, 4], @tm.subscribers(@uri)
      assert_same_elements [2, 3], @tm.subscribers(@uri, 10)
    end

    should 'calculate the number of expected content items' do
      assert_equal 3, @tm.expectedContentItemCount
    end

    should 'calculate the number of successfully delivered content items' do
      assert_equal 2, @tm.deliveredContentItemCount
    end

    should 'calculate the delivery ratio for content items' do
      assert_equal 2/3.0, @tm.contentItemDeliveryRatio
    end

    should 'calculate the delays for delivery content items' do
      assert_equal [1, 8], @tm.contentItemDelays
    end

    should 'calculate the bytes cached for all nodes and all sample times' do
      assert_same_elements [4, 4, 4, 4, 0, 0, 4, 0], @tm.cacheUse(5)
    end

    should 'calculate transmissions per content item' do
      assert_equal [4], @tm.transmissionsPerContentItem
    end

    should 'track revisions' do
      assert(!@tm.contentItem(@uri).delivered?(3, nil, :revision => 1))
      assert @tm.contentItem(@uri).delivered?(2, nil, :revision => 1)
    end

    should 'take deletions into account'

  end
  
end

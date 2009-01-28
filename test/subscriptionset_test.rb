$:.unshift File.join(File.dirname(__FILE__), "..", "lib")

require 'rubygems'
require "test/unit"
require 'shoulda'
require "subscriptionset"
require "daemon"

class TestSubscriptionSet < Test::Unit::TestCase

  def setup
    @daemon = RdtnDaemon::Daemon.new("dtn://receiver.dtn/")
    @subSet = SubscriptionSet.new(@daemon.config, @daemon.evDis)
  end

  should 'save subscriptions' do
    uri = 'dtn://channel1/'
    assert !@subSet.subscribed?(uri)
    @subSet.subscribe uri
    assert @subSet.subscribed?(uri)
  end

  should 'store information about individual subscribers' do
    uri  = 'dtn://channel1/'
    node = 'dtn://node1/'
    @subSet.subscribe uri
    @subSet.subscribe uri, node

    assert_same_elements [node, @daemon.config.localEid],
      @subSet.subscribers(uri)
  end

  should 'allow unsubscribing' do
    uri1 = 'dtn://channel1/'
    uri2 = 'dtn://channel2/'
    node = 'dtn://node1/'
    @subSet.subscribe uri1
    @subSet.subscribe uri1, node
    @subSet.subscribe uri2

    @subSet.unsubscribe uri1

    assert @subSet.subscribed?(uri1)
    assert_equal [node], @subSet.subscribers(uri1)
    assert @subSet.subscribed?(uri2)
    @subSet.unsubscribe uri2
    assert !@subSet.subscribed?(uri2)
  end

  should 'delete expired subscriptions' do
    uri = 'dtn://channel1/'
    node = 'dtn://node1/'
    @subSet.subscribe uri
    @subSet.subscribe uri, node, :expires => Time.now - 1
    assert_same_elements [node, @daemon.config.localEid],
      @subSet.subscribers(uri)
    @subSet.housekeeping!
    assert_same_elements [@daemon.config.localEid], @subSet.subscribers(uri)
  end 

  should 'save the delays between when a subscription was created and when it reached the local node' do
    uri  = 'dtn://channel1/'
    node = 'dtn://node1/'
    @subSet.subscribe uri
    @subSet.subscribe uri, node, :created => RdtnTime.now - 100
    assert_equal({@daemon.config.localEid => 0, node => 100},
      @subSet.delays(uri))
  end

  should 'save the hop count from the origin of the subscription' do
    uri  = 'dtn://channel1/'
    node = 'dtn://node1/'
    @subSet.subscribe uri
    @subSet.subscribe uri, node, :hopCount => 10
    assert_equal({@daemon.config.localEid => 0, node => 10},
      @subSet.hopCounts(uri))
  end

  context 'After importing subscriptions from another node, the SubscriptionSet' do

    setup do
      @uri1        = 'dtn://channel1/'
      @uri2        = 'dtn://channel2/'
      @uri3        = 'dtn://channel3/'
      @node3       = 'dtn:/node3.dtn/'
      @daemon2     = RdtnDaemon::Daemon.new("dtn://node2.dtn/")
      @subSet2 = SubscriptionSet.new(@daemon2.config, @daemon2.evDis)

      @subSet.subscribe  @uri1
      @subSet2.subscribe @uri1
      @subSet2.subscribe @uri2, @node3, :hopCount => 1, :created => RdtnTime.now - 100, :delay => 50
      @subSet.subscribe  @uri3, @node3, :hopCount => 1, :created => RdtnTime.now - 100
      @subSet2.subscribe @uri3, @node3, :hopCount => 1, :created => RdtnTime.now - 50

      @subSet.import @subSet2
    end

    should 'subscribe to the union of the channels of both nodes' do
      assert @subSet.subscribed?(@uri1)
      assert @subSet.subscribed?(@uri2)
      assert_same_elements [@daemon2.config.localEid, @daemon.config.localEid],
	@subSet.subscribers(@uri1)
      assert_same_elements [@node3], @subSet.subscribers(@uri2)
    end

    should 'increment the hop count from the imported nodes' do
      assert_equal 2, @subSet.hopCounts(@uri2)[@node3]
    end

    should 'calculate the delay independent from the importet value' do
      assert_equal 100, @subSet.delays(@uri2)[@node3]
    end

    should 'use the optimal hop count as local value' do
      assert_equal 1, @subSet.hopCounts(@uri3)[@node3]
    end

    should 'use the optimal delay as local value' do
      assert_equal 50, @subSet.delays(@uri3)[@node3]
    end

  end

  should 'marshal and load subscriptions' do
    require 'yaml'

    uri  = 'dtn://channel1/'
    node = 'dtn://node1/'
    @subSet.subscribe uri
    @subSet.subscribe uri, node

    dump    = YAML.dump @subSet
    subset2 = YAML.load dump

    assert_same_elements [node,@daemon.config.localEid],subset2.subscribers(uri)
  end

end

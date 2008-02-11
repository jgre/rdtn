#  Copyright (C) 2007 Janico Greifenberg <jgre@jgre.org> and 
#  Dirk Kutscher <dku@tzi.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

$:.unshift File.join(File.dirname(__FILE__), "..", "lib")

require "test/unit"
require "subscriptionhandler"
require "bundle"
require "storage"

class MockLink < Link
  attr_accessor :remoteEid, :bundle, :bundles

  def initialize(config, evDis)
    @bundles = []
    super(config, evDis)
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

class MockClient
  attr_accessor :uri, :subscriptions

  def initialize
    @subscriptions = []
  end

  def register(eid, &handler)
    @uri = eid
    @handler = handler
  end

  def addRoute(uri, target)
    @subscriptions.push(uri)
  end

  def sendBundle(bundle)
    bundle.incomingLink = self
    @handler.call(bundle)
  end

  def deleteBundle(id)
  end
end

class MockContactManager

  def initialize(link)
    @link = link
  end

  def findLinkByName(name)
    return @link
  end
end

class TestSubscriptionHandler < Test::Unit::TestCase

  Uris = ["dtn://test1/", "dtn://test2", "http://tzi.org"]

  def setup
    @evDis  = EventDispatcher.new
    @config = RdtnConfig::Settings.new(@evDis)
    @client = MockClient.new
    @config.store = Storage.new(@evDis)
    @shandler = SubscriptionHandler.new(@config, @evDis, nil, 2)
    @config.subscriptionHandler = @shandler
    Uris.each {|uri| @shandler.subscribe(uri, MockClient.new)}
  end

  def teardown
    #RdtnConfig::Settings.instance.store.clear
    #begin
    #  File.delete("store")
    #rescue
    #end
  end

  def test_subscribe
    # Add a duplicate
    @shandler.subscribe(Uris[0])
    assert_equal(Uris, @shandler.subscribedUris)
  end

  def test_subscription_bundles
    shandler2 = SubscriptionHandler.new(@config, @evDis, nil)

    # Feed the subscription bundle of the first handler to the client of the
    # second one.
    eid = "dtn://firstSubscriber/"
    bundle = @shandler.generateSubscriptionBundle
    bundle.srcEid = eid
    shandler2.processBundle(bundle)
    assert_equal(Uris, shandler2.neighborSubs[eid].subscribedUris)
    assert_equal(Uris, shandler2.subscribedUris)
  end

  def test_merge
    addUri = "dtn://something.else/"
    slist1 = SubscriptionList.new(nil)
    slist2 = SubscriptionList.new(nil)
    Uris.each do |uri|
      sub = Subscription.new(@config, @evDis, uri)
      slist1.addSubscription(sub)
      sub.uniqueSubscriptions.push(UniqueSubscription.new(nil,"dtn:none",true))
      sub.uniqueSubscriptions.push(UniqueSubscription.new(nil,"dtn:none",false))
    end
    Uris[0..1].each do |uri| 
      sub = Subscription.new(@config, @evdis, uri)
      slist2.addSubscription(sub)
      sub.uniqueSubscriptions.push(UniqueSubscription.new(nil,"dtn:none",false))
      sub.uniqueSubscriptions.push(UniqueSubscription.new(nil,"dtn:none",false))
    end
    sub = Subscription.new(@config, @evDis, addUri)
    slist2.addSubscription(sub)
    sub.uniqueSubscriptions.push(UniqueSubscription.new(nil,"dtn:none",false))
    slist2.subscriptions[0].addBundleReceived("1234")
    slist2.subscriptions[0].addBundleReceived("9876")

    slist1.merge(slist2)

    assert_equal(Uris + [addUri], slist1.subscribedUris)
    slist2.bundlesReceived.each {|br| assert(slist2.bundleReceived?(br))}
    #FIXME: What does this mean?
    #slist2.bundlesReceived.each {|br| assert((not slist1.bundleReceived?(br)))}

    slist2.subscriptions.each do |sub2|
      sub1 = slist1.findSubscription {|sub| sub.uri == sub2.uri}
      assert(sub1)
      usubs1 = sub1.uniqueSubscriptions.map {|usub| usub.uid}
      usubs2 = sub2.uniqueSubscriptions.map {|usub| usub.uid}
      usubs2.each {|us| assert(usubs1.include?(us))}
    end
  end

  def test_subscription_bundle_data
    sub = Subscription.new(@config, @evDis, Uris[0])
    io = RdtnStringIO.new
    sub.addBundleReceived("1234")
    sub.addBundleReceived("9876")
    sub.uniqueSubscriptions.push(UniqueSubscription.new(nil,"dtn:none",true))
    sub.serialize(io)
    io.rewind
    sleep(1)
    sub2 = Subscription.parse(@config, @evDis, io)
    assert_equal(sub.uri.to_s, sub2.uri.to_s)
    #assert_equal(sub.uids, sub2.uids)
    assert_equal(sub.creationTimestamp.to_i, sub2.creationTimestamp.to_i)
    assert_equal(sub.expires.to_i, sub2.expires.to_i)
    assert_equal(sub.hopCount, sub2.hopCount)
    assert_equal(sub.bundlesReceived, sub2.bundlesReceived)
  end

  def test_check
    shortUri = "dtn://shortlived"
    # Add a subscription that expires soon
    @shandler.subscribe(shortUri, MockClient.new, Time.now, Time.now + 1)
    assert_equal(Uris + [shortUri], @shandler.subscribedUris)
    sleep(3)
    assert_equal(Uris, @shandler.subscribedUris)

  end

end

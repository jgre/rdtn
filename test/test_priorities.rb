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

class TestPriorities < Test::Unit::TestCase

  Uris = ["dtn://test1/", "dtn://test2", "http://tzi.org"]
  LocalEid = "dtn://local/"
  Neighbor1Eid = "dtn://neighbor1"
  Neighbor2Eid = "dtn://neighbor2"
  SenderEid = "dtn://sender"

  def setup
    @evDis  = EventDispatcher.new
    @config = RdtnConfig::Settings.new(@evDis)
    @eid = "dtn://test/bla"
    @config.localEid = @eid
    @bundles = Uris.map {|uri| Bundling::Bundle.new("abc", uri, SenderEid)}
    @bundles.each_with_index do |b, i| 
      b.creationTimestamp = (Time.now - Time.gm(2000)).to_i + i*10
    end
    @bundles[1].lifetime = 3000
    @bundles[0].lifetime = 3600
    @bundles[2].lifetime = 3700
    @subHandler = SubscriptionHandler.new(@config, @evDis, nil)
    @config.subscriptionHandler = @subHandler
    @subHandler.subscribe(Uris[0])
    @subscriptions = Uris.map {|uri| Subscription.new(@config, @evDis, uri)}
    usub0local = UniqueSubscription.new(nil, @eid)
    usub0remote = UniqueSubscription.new(nil, @eid, false,Time.now,Time.now+3600,10)
    usub1local = UniqueSubscription.new(nil,@eid, true,Time.now-3600,Time.now+3600)
    usub1remote = UniqueSubscription.new(nil,@eid, false,Time.now-3600,Time.now+3600,10)
    usub2local = UniqueSubscription.new(nil, @eid)
    usub2remote = UniqueSubscription.new(nil,@eid,false,Time.now,Time.now+3600,10)

    sub10 = @subscriptions[1].copy
    sub20 = @subscriptions[2].copy
    sub10.uniqueSubscriptions.push(usub1remote)
    sub10.uniqueSubscriptions.push(usub1remote.copy)
    sub20.uniqueSubscriptions.push(usub2local)
    sub20.uniqueSubscriptions.push(usub2local.copy)
    sub20.uniqueSubscriptions.push(usub2local.copy)
    @subHandler.mySubs.addSubscription(sub10)
    @subHandler.mySubs.addSubscription(sub20)

    @subscriptions[1].uniqueSubscriptions.push(usub1local)
    @subscriptions[1].addBundleReceived(@bundles[1].bundleId)
    sub11 = @subscriptions[1].copy
    sub11.bundlesReceived = []

    @n1subs = SubscriptionList.new(nil, Neighbor1Eid)
    @n1subs.addSubscription(@subscriptions[1])
    @subHandler.neighborSubs[Neighbor1Eid] = @n1subs

    @subscriptions[2].uniqueSubscriptions.push(usub2remote)
    @n2subs = SubscriptionList.new(nil, Neighbor2Eid)
    @n2subs.addSubscription(@subscriptions[2])
    @subHandler.neighborSubs[Neighbor2Eid] = @n2subs
  end

  def test_resend_filter
    filter = DuplicateFilter.new(@config, @evDis, @subHandler)
    # find_all returns the elements that are removed by delete_if
    res1=@bundles.find_all {|bundle| filter.filterBundle?(bundle,Neighbor1Eid)}
    assert_equal([@bundles[1]], res1)
    res2=@bundles.find_all {|bundle| filter.filterBundle?(bundle,Neighbor2Eid)}
    assert(res2.empty?)
  end

  def test_not_subscribed_filter
    filter = KnownSubscriptionFilter.new(@config, @evDis, @subHandler)
    res1=@bundles.find_all {|bundle| filter.filterBundle?(bundle,Neighbor1Eid)}
    assert_equal([@bundles[0], @bundles[2]], res1)
    res2=@bundles.find_all {|bundle| filter.filterBundle?(bundle,Neighbor2Eid)}
    assert_equal([@bundles[0], @bundles[1]], res2)
  end

  def test_hop_count_filter
    filter = HopCountFilter.new(@config, @evDis, @subHandler)
    res1=@bundles.find_all {|bundle| filter.filterBundle?(bundle,Neighbor1Eid)}
    assert(res1.empty?)
    res2=@bundles.find_all {|bundle| filter.filterBundle?(bundle,Neighbor2Eid)}
    assert_equal([@bundles[2].bundleId], res2.map{|b| b.bundleId})
  end

  def test_bundle_time_filter
    filter = BundleTimeFilter.new(@config, @evDis, @subHandler)
    res1=@bundles.find_all {|bundle| filter.filterBundle?(bundle,Neighbor1Eid)}
    assert_equal([@bundles[1].destEid], res1.map{|b| b.destEid})
  end

  def test_hop_count_prio
    prio = SubscriptionHopCountPrio.new(@config, @evDis, @subHandler)
    res1 = @bundles.sort {|b1, b2| prio.orderBundles(b1, b2, Neighbor1Eid)}
    assert_equal([@bundles[1], @bundles[0], @bundles[2]], res1)
    res2 = @bundles.sort {|b1, b2| prio.orderBundles(b1, b2, Neighbor2Eid)}
    assert_equal([@bundles[0], @bundles[2], @bundles[1]], res2)
  end

  def test_unique_subscriber_prio
    prio = PopularityPrio.new(@config, @evDis, @subHandler)
    res1 = @bundles.sort {|b1, b2| prio.orderBundles(b1, b2, Neighbor1Eid)}
    assert_equal([@bundles[2], @bundles[1], @bundles[0]], res1)
    res2 = @bundles.sort {|b1, b2| prio.orderBundles(b1, b2, Neighbor2Eid)}
    assert_equal(res1, res2)
  end

  def test_bundle_time_prio_old
    prio = LongDelayPrio.new(@config, @evDis, @subHandler)
    res1 = @bundles.sort {|b1, b2| prio.orderBundles(b1, b2, Neighbor1Eid)}
    assert_equal(@bundles, res1)
  end

  def test_bundle_time_prio_new
    prio = ShortDelayPrio.new(@config, @evDis, @subHandler)
    res1 = @bundles.sort {|b1, b2| prio.orderBundles(b1, b2, Neighbor1Eid)}
    assert_equal(@bundles.reverse, res1)
  end

end


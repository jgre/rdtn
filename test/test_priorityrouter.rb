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
require "bundle"
require "queue"
require "priorityrouter"
require "bundleworkflow"
require "storage"
require "subscriptionhandler"

class MockLink < Link
  attr_accessor :remoteEid, :bundle

  def initialize
    super
    @bundles = []
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

class MockStore
end

class MockContactManager

  def initialize(link)
    @link = link
  end

  def findLinkByName(name)
    return @link
  end
end

class TestPriorityRouter < Test::Unit::TestCase

  def setup
    @link1 = MockLink.new
    @link1.remoteEid = "dtn:oink"
    @link2 = MockLink.new
    @link2.remoteEid = "dtn:grunt"
    @link3 = MockLink.new
    @link3.remoteEid = "dtn:grunt3"
    RdtnConfig::Settings.instance.store = Storage.new
    @contactManager = MockContactManager.new(@link1)
    RdtnConfig::Settings.instance.contactManager = @contactManager
    @subHandler = SubscriptionHandler.new(nil, nil)
    RdtnConfig::Settings.instance.subscriptionHandler = @subHandler
    @routeTab = PriorityRouter.new(@contactManager)
  end

  def teardown
    RdtnConfig::Settings.instance.store.clear
    EventDispatcher.instance.clear
  end

  def test_forward
    store = RdtnConfig::Settings.instance.store
    bndl = Bundling::Bundle.new("test", "dtn:receiver")
    bndl2 = Bundling::Bundle.new("test", "dtn:receiver2")
    store.storeBundle(bndl)
    store.storeBundle(bndl2)
    @routeTab.priorities.push(LongDelayPrio.new)
    @routeTab.priorities.push(SubscriptionHopCountPrio.new)
    @routeTab.priorities.push(PopularityPrio.new)
    #@routeTab.forwardBundles(nil, [@link1])
    EventDispatcher.instance.dispatch(:neighborContact, nil, @link1)

    assert_equal(@link1.bundle.to_s, bndl2.to_s)
  end

  def test_filter
    store = RdtnConfig::Settings.instance.store
    bndl = Bundling::Bundle.new("test", "dtn:receiver")
    store.storeBundle(bndl)
    @routeTab = PriorityRouter.new(@contactManager)
    @routeTab.filters.push(KnownSubscriptionFilter.new)
    #@routeTab.forwardBundles(nil, [@link1])
    EventDispatcher.instance.dispatch(:neighborContact, nil, @link1)

    assert_equal(@link1.bundle.to_s, bndl.to_s)
  end

  def test_local_registrations
    Bundling::BundleWorkflow.registerEvents
    appIf = AppIF::AppInterface.new("client0", :port => 12345)
    client = RdtnClient.new("localhost", 12345)
    eid = "dtn://test/receiver"
    b=Bundling::Bundle.new("test", eid)
    client2 = RdtnClient.new(client.host, client.port)
    client2.sendBundle(b)
    sleep(1)
    eventSent = false
    client.register(eid) do |bundle|
      eventSent = true
      assert_equal(b.payload.length, bundle.payload.length)
    end
    sleep(1)
    assert(eventSent)
  end

end


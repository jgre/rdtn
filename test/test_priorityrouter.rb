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

  def initialize(config, evDis)
    super(config, evDis)
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
    @evDis  = EventDispatcher.new
    @config = RdtnConfig::Settings.new(@evDis)
    @link1 = MockLink.new(@config, @evDis)
    @link1.remoteEid = "dtn:oink"
    @link2 = MockLink.new(@config, @evDis)
    @link2.remoteEid = "dtn:grunt"
    @link3 = MockLink.new(@config, @evDis)
    @link3.remoteEid = "dtn:grunt3"
    @config.store = Storage.new(@evDis)
    @contactManager = MockContactManager.new(@link1)
    @config.contactManager = @contactManager
    @subHandler = SubscriptionHandler.new(@config, @evDis, nil)
    @config.subscriptionHandler = @subHandler
    @routeTab = PriorityRouter.new(@config, @evDis, @contactManager)
  end

  def teardown
    @config.store.clear
  end

  def test_forward
    store = @config.store
    bndl = Bundling::Bundle.new("test", "dtn:receiver")
    bndl2 = Bundling::Bundle.new("test", "dtn:receiver2")
    store.storeBundle(bndl)
    store.storeBundle(bndl2)
    @routeTab.priorities.push(LongDelayPrio.new(@config, @evDis, @subHandler))
    @routeTab.priorities.push(SubscriptionHopCountPrio.new(@config, @evDis, @subHandler))
    @routeTab.priorities.push(PopularityPrio.new(@config, @evDis, @subHandler))
    #@routeTab.forwardBundles(nil, [@link1])
    @evDis.dispatch(:neighborContact, nil, @link1)

    assert(@link1.received?(bndl))
    assert(@link1.received?(bndl2))
  end

  def test_filter
    store = @config.store
    bndl = Bundling::Bundle.new("test", "dtn:receiver")
    store.storeBundle(bndl)
    @routeTab = PriorityRouter.new(@config, @evDis, @contactManager, 
				   @subHandler)
    @routeTab.filters.push(KnownSubscriptionFilter.new(@config, @evDis, 
						       @subHandler))
    #@routeTab.forwardBundles(nil, [@link1])
    @evDis.dispatch(:neighborContact, nil, @link1)

    assert(@link1.received?(bndl))
  end

  def test_local_registrations
    Bundling::BundleWorkflow.registerEvents(@config, @evDis)
    appIf = AppIF::AppInterface.new(@config, @evDis, "client0", :port => 12345)
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


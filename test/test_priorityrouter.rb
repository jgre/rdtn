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
require "daemon"

module TestPrioRoute
  class MockLink < Link
    attr_accessor :remoteEid, :bundle

    def initialize(config, evDis, eid)
      super(config, evDis)
      @bundles = []
      @remoteEid = eid
      @evDis.dispatch(:linkOpen, self)
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
end

class TestPriorityRouter < Test::Unit::TestCase

  def setup
    @daemon = RdtnDaemon::Daemon.new("dtn://test.sender")
    @evDis  = @daemon.evDis
    @config = @daemon.config
    @config.contactManager
    @link1 = TestPrioRoute::MockLink.new(@config, @evDis, "dtn:oink")
    @link2 = TestPrioRoute::MockLink.new(@config, @evDis, "dtn:grunt")
    @link3 = TestPrioRoute::MockLink.new(@config, @evDis, "dtn:grunt3")
    Storage.new(@config, @evDis)
    @subHandler = SubscriptionHandler.new(@config, @evDis, nil)
    @routeTab = PriorityRouter.new(@daemon)
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
    @evDis.dispatch(:neighborContact, Neighbor.new(@link1.remoteEid), @link1)
    @evDis.dispatch(:subscriptionsReceived, @link1.remoteEid)

    assert(@link1.received?(bndl))
    assert(@link1.received?(bndl2))
  end

  def test_filter
    store = @config.store
    bndl = Bundling::Bundle.new("test", "dtn:receiver")
    store.storeBundle(bndl)
    store.each(true) do |b|
      rdebug(self, "Bundle #{b.bundleId}: #{b.srcEid} -> #{b.destEid}")
    end

    rdebug(self, "Test Store #{store.object_id}")
    @routeTab = PriorityRouter.new(@daemon)
    @routeTab.filters.push(KnownSubscriptionFilter.new(@config, @evDis, 
						       @subHandler))
    #@routeTab.forwardBundles(nil, [@link1])
    rdebug(self, "test_filter: dispatching :neighborContact")
    @evDis.dispatch(:neighborContact, Neighbor.new("dtn://neighbor"), @link1)

    rdebug(self, "test_filter end")
    assert((not @link1.received?(bndl)))
  end

  def test_local_registrations
    eid = "dtn://test/receiver"
    daemon = RdtnDaemon::Daemon.new(eid)
    b=Bundling::Bundle.new("test", eid)
    eventSent = false
    daemon.sendBundle(b)
    daemon.register(eid) do |bundle|
      eventSent = true
      assert_equal(b.payload.length, bundle.payload.length)
    end
    assert(eventSent)
  end

end


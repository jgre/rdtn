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
require "routetab"
require "bundleworkflow"

class MockLink < Link
  attr_accessor :remoteEid

  def initialize(config, evDis, eid)
    super(config, evDis)
    @remoteEid = eid
    @bundles = []
  end

  def sendBundle(bundle)
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

class TestRoutetab < Test::Unit::TestCase

  def setup
    @evDis  = EventDispatcher.new
    @config = RdtnConfig::Settings.new(@evDis)
    @link1 = MockLink.new(@config, @evDis, "dtn:oink")
    @link2 = MockLink.new(@config, @evDis, "dtn:grunt")
    @link3 = MockLink.new(@config, @evDis, "dtn:grunt3")
    @config.store = Storage.new(@evDis, nil, "store")
    @contactManager = MockContactManager.new(@link1)
    @routeTab = RoutingTable.new(@config, @evDis)
  end

  def teardown
    begin
      File.delete("store")
    rescue
    end
  end

  def test_forward
    bndl = Bundling::Bundle.new("test", "dtn:receiver")
    @routeTab.addEntry(RoutingEntry.new(".*receiver", @link1))
    @routeTab.forward(bndl)

    assert(@link1.received?(bndl))
  end

  def test_delayed_forward

    store = @config.store
    # Initialize routing table
    Bundling::BundleWorkflow.registerEvents(@config, @evDis)
    bndl = Bundling::Bundle.new("test", "dtn:receiver")
    # Dispatch event so that the bundle is written to the store
    @evDis.dispatch(:bundleParsed, bndl)
    @routeTab.addEntry(RoutingEntry.new(".*receiver", @link1))

    #assert(@link1.bundle.payload == "test")
    assert(@link1.received?(bndl))
  end

  def test_multiple_destinations
    bndl = Bundling::Bundle.new("test", "dtn:receiver")
    @routeTab.addEntry(RoutingEntry.new(".*receiver", @link1))
    @routeTab.addEntry(RoutingEntry.new(".*receiver", @link2))
    @routeTab.forward(bndl)

    assert(@link1.received?(bndl))
    # When we use a forwarding based scheme (like routetab), there may only be a
    # single copy of the bundle.
    assert((not @link2.received?(bndl)))
  end

  def test_exclusive
    bndl = Bundling::Bundle.new("test", "dtn:receiver")
    @routeTab.addEntry(RoutingEntry.new(".*receiver", @link1))
    @routeTab.addEntry(RoutingEntry.new(".*receiver", @link2, true))
    @routeTab.forward(bndl)

    #assert_nil(@link1.bundle)
    assert((not @link1.received?(bndl)))
    assert(@link2.received?(bndl))
  end

  def test_delete
    bndl = Bundling::Bundle.new("test", "dtn:receiver")
    bndl2 = Bundling::Bundle.new("test2", "dtn:rcv")
    @routeTab.addEntry(RoutingEntry.new(".*receiver", @link1))
    @routeTab.addEntry(RoutingEntry.new(".*receiver", @link2))
    @routeTab.addEntry(RoutingEntry.new(".*rcv", @link2))
    @routeTab.addEntry(RoutingEntry.new(".*receiver", @link3))
    @routeTab.deleteEntry(@link1)
    @routeTab.deleteEntry(@link2, ".*receiver")
    @routeTab.forward(bndl)
    @routeTab.forward(bndl2)

    assert(@link1.received?(bndl) == false)
    assert(@link1.received?(bndl2) == false)
    assert(@link2.received?(bndl) == false)
    assert(@link2.received?(bndl2))
    assert(@link3.received?(bndl))
    assert(@link3.received?(bndl2) == false)
  end

end

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

class TestRoutetab < Test::Unit::TestCase

  def setup
    @link1 = MockLink.new
    @link1.remoteEid = "dtn:oink"
    @link2 = MockLink.new
    @link2.remoteEid = "dtn:grunt"
    @link3 = MockLink.new
    @link3.remoteEid = "dtn:grunt3"
    RdtnConfig::Settings.instance.store = Storage.new(nil, "store")
    @contactManager = MockContactManager.new(@link1)
  end

  def teardown
    RdtnConfig::Settings.instance.store.clear
    begin
      File.delete("store")
    rescue
    end
    EventDispatcher.instance.clear
  end

  def test_forward
    @routeTab = RoutingTable.new(@contactManager)
    bndl = Bundling::Bundle.new("test", "dtn:receiver")
    @routeTab.addEntry(RoutingEntry.new(".*receiver", @link1))
    @routeTab.forward(bndl)

    assert(@link1.bundle.to_s == bndl.to_s)
  end

  def test_delayed_forward

    store = RdtnConfig::Settings.instance.store
    # Initialize routing table
    @routeTab = RoutingTable.new(@contactManager)
    Bundling::BundleWorkflow.registerEvents
    bndl = Bundling::Bundle.new("test", "dtn:receiver")
    # Dispatch event so that the bundle is written to the store
    EventDispatcher.instance.dispatch(:bundleParsed, bndl)
    @routeTab.addEntry(RoutingEntry.new(".*receiver", @link1))

    assert(@link1.bundle.payload == "test")
  end

  def test_multiple_destinations
    @routeTab = RoutingTable.new(@contactManager)
    bndl = Bundling::Bundle.new("test", "dtn:receiver")
    @routeTab.addEntry(RoutingEntry.new(".*receiver", @link1))
    @routeTab.addEntry(RoutingEntry.new(".*receiver", @link2))
    @routeTab.forward(bndl)

    assert(@link1.bundle.to_s == bndl.to_s)
    assert(@link2.bundle.to_s == bndl.to_s)
  end

  def test_exclusive
    assert_nil(@link1.bundle)
    @routeTab = RoutingTable.new(@contactManager)
    bndl = Bundling::Bundle.new("test", "dtn:receiver")
    @routeTab.addEntry(RoutingEntry.new(".*receiver", @link1))
    @routeTab.addEntry(RoutingEntry.new(".*receiver", @link2, true))
    @routeTab.forward(bndl)

    assert_nil(@link1.bundle)
    assert(@link2.bundle.to_s == bndl.to_s)
  end

  def test_delete
    @routeTab = RoutingTable.new(@contactManager)
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

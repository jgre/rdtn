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
#
# $Id$

$:.unshift File.join(File.dirname(__FILE__), "..", "lib")

require "test/unit"
require "bundle"
require "queue"
require "routetab"

class DummyLink < Link
  attr_accessor :remoteEid, :bundle

  def sendBundle(bundle)
    @bundle = bundle
  end

end

class TestRoutetab < Test::Unit::TestCase

  def setup
    @link1 = DummyLink.new
    @link1.remoteEid = "dtn:oink"
    @link2 = DummyLink.new
    @link2.remoteEid = "dtn:grunt"
  end

  def test_forward
    bndl = Bundling::Bundle.new("test", "dtn:receiver")
    RoutingTable.instance.addEntry(".*receiver", @link1)
    EventDispatcher.instance.dispatch(:bundleParsed, bndl)

    EventLoop.after(1) { EventLoop.quit }
    EventLoop.run

    assert(@link1.bundle.payload == "test")
  end

  def test_delayed_forward

    RDTNConfig.instance.storageDir = "store"
    # Initialize routing table
    store = Storage.instance
    router = RoutingTable.instance
    bndl = Bundling::Bundle.new("test", "dtn:receiver")
    EventDispatcher.instance.dispatch(:bundleParsed, bndl)

    EventLoop.after(1) { RoutingTable.instance.addEntry(".*receiver", @link1) }
    EventLoop.after(2) { EventLoop.quit }
    EventLoop.run

    assert(@link1.bundle.payload == "test")
  end

end

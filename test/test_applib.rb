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
require "clientregcl"
require "clientlib"

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

class MockContactManager

  def initialize(link)
    @link = link
  end

  def findLinkByName(name)
    return @link
  end
end

class TestAppLib < Test::Unit::TestCase

  def setup
    @appIf = AppIF::AppInterface.new("client0", :port => 12345)
    @client = RdtnClient.new("localhost", 12345)
    @bundleContent="test!"
    begin
      @bundleContent = open(File.join(File.dirname(__FILE__), "mbfile")) do |f|
	f.read
      end
    rescue
    end
  end

  def teardown
    EventDispatcher.instance.clear
    if RdtnConfig::Settings.instance.store
      RdtnConfig::Settings.instance.store.clear 
    end
    @client.close
    @appIf.close
  end

  def test_send_bundle

    bundleOrig="dtn://bla.fasel"

    eventSent = false
    b=Bundling::Bundle.new(@bundleContent, bundleOrig)

    EventDispatcher.instance.subscribe(:bundleParsed) do |bundle|
      assert_equal(b.to_s, bundle.to_s)
      eventSent = true
    end
    @client.sendBundle(b)

    sleep(1)
    assert(eventSent)
  end

  def test_receive_bundle
    router = RoutingTable.new(nil)
    eid = "dtn://test/receiver"
    eventSent = false
    b=Bundling::Bundle.new(@bundleContent, eid)
    @client.register(eid) do |bundle|
      eventSent = true
      assert_equal(bundle.payload.length, bundle.payload.length)
    end
    client2 = RdtnClient.new(@client.host, @client.port)
    client2.sendBundle(b)
    sleep(1)
    assert(eventSent)
  end

  def test_unregister
    router = RoutingTable.new(nil)
    eid = "dtn://test/receiver"
    b=Bundling::Bundle.new(@bundleContent, eid)
    @client.register(eid) do |bundle|
      flunk
    end
    @client.unregister(eid)
    client2 = RdtnClient.new(@client.host, @client.port)
    client2.sendBundle(b)
    sleep(1)
  end

  def test_add_route
    eid = "dtn://test/receiver"
    link = MockLink.new
    router = RoutingTable.new(MockContactManager.new(link))
    b=Bundling::Bundle.new(@bundleContent, eid)

    @client.addRoute(eid, link.name)

    sleep(1)
    @client.sendBundle(b)

    sleep(1)
    assert(link.received?(b))
  end

  def test_del_route
    eid = "dtn://test/receiver"
    link = MockLink.new
    router = RoutingTable.new(MockContactManager.new(link))
    b=Bundling::Bundle.new(@bundleContent, eid)

    @client.addRoute(eid, link.name)
    @client.delRoute(eid, link.name)

    sleep(1)
    @client.sendBundle(b)

    sleep(1)
    assert((not link.received?(b)))
  end

  def test_subscribe_event
    a = 1
    b = 2
    c = 3
    eventSent = false
    @client.subscribeEvent(:bogusEvent) do |aa, bb, cc|
      assert_equal(a, aa)
      assert_equal(b, bb)
      assert_equal(c, cc)
      eventSent = true
    end
    sleep(1)
    EventDispatcher.instance.dispatch(:bogusEvent, a, b, c)
    sleep(1)
    assert(eventSent)
  end

  def test_delete_bundle
    eid = "dtn://test/receiver"
    b=Bundling::Bundle.new(@bundleContent, eid)
    store = Storage.new
    RdtnConfig::Settings.instance.store = store
    store.storeBundle(b)
    @client.deleteBundle(b.bundleId)
    assert_nil(store.getBundle(b.bundleId))
  end

end

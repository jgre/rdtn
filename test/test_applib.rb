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
require "bundleworkflow"
require "daemon"

class TestAppLib < Test::Unit::TestCase

  def setup
    @daemon = RdtnDaemon::Daemon.new("dtn://test.sender")
    @evDis  = @daemon.evDis
    @config = @daemon.config
    @appIf  = AppIF::AppInterface.new(@config, @evDis, "client0", 
				      :port=>12345, :daemon=>@daemon)
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
    @client.close
    @appIf.close
  end

  def test_send_bundle

    bundleOrig="dtn://bla.fasel"

    eventSent = false
    b=Bundling::Bundle.new(@bundleContent, bundleOrig, @config.localEid)

    @evDis.subscribe(:bundleParsed) do |bundle|
      assert_equal(b.to_s, bundle.to_s)
      eventSent = true
    end
    @client.sendBundle(b)

    sleep(1)
    assert(eventSent)
  end

  def test_send_data

    bundleOrig="dtn://bla.fasel"

    eventSent = false

    @evDis.subscribe(:bundleParsed) do |bundle|
      assert_equal(@bundleContent, bundle.payload)
      assert_equal(bundleOrig, bundle.destEid.to_s)
      assert_equal(@config.localEid.to_s, bundle.srcEid.to_s)
      eventSent = true
    end
    @client.sendDataTo(@bundleContent, bundleOrig, @config.localEid)

    sleep(1)
    assert(eventSent)
  end

  def test_receive_bundle
    eid = "dtn://test/receiver"
    eventSent = false
    b=Bundling::Bundle.new(@bundleContent, eid)
    @client.register(eid) do |bundle|
      eventSent = true
      assert_equal(bundle.payload, b.payload)
    end
    client2 = RdtnClient.new(@client.host, @client.port)
    client2.sendBundle(b)
    sleep(1)
    assert(eventSent)
  end

  def test_unregister
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

  def test_delete_bundle
    eid = "dtn://test/receiver"
    b=Bundling::Bundle.new(@bundleContent, eid)
    Storage.new(@config, @evDis)
    @config.store.storeBundle(b)
    @client.deleteBundle(b.bundleId)
    sleep(1)
    assert_nil(@config.store.getBundle(b.bundleId))
  end

end

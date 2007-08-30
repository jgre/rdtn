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

class BDummyLink
  def initialize#(&prc)
    #@prc = prc
  end

  def bytesToRead=(bytes)
    #@prc.call
  end
end

class TestBundle < Test::Unit::TestCase

  def setup
    @inBundle = "\004\020\000\000J\000\000\000\004\000\000\000\026\000\000\000\026\000\000\000(\r\213\274\f\000\000\000\001\000\000\016\020-dtn\000//domain.dtn/test\000//hamlet.dtn/test\000none\000\001\010\003bla"
  end

  def teardown
    EventDispatcher.instance.clear
  end

  def test_parser
    bundle = Bundling::Bundle.new
    bundle.parse(StringIO.new(@inBundle))

    assert_instance_of(Bundling::AnyBlock, bundle.state)
    assert_equal(4, bundle.version)
    assert_equal(-1, bundle.bytesToRead)
    #TODO check flags
    assert_equal("dtn://domain.dtn/test", bundle.destEid.to_s)
    assert_equal("dtn://hamlet.dtn/test", bundle.srcEid.to_s)
    assert_equal("dtn://hamlet.dtn/test", bundle.reportToEid.to_s)
    assert_equal("dtn:none", bundle.custodianEid.to_s)
    assert_equal("bla", bundle.payload)
  end

  def test_in_out
    bundle = Bundling::Bundle.new
    bundle.parse(StringIO.new(@inBundle))
    outStr = bundle.to_s
    assert_equal(@inBundle, outStr)
  end

  def test_bundle_events
    bl = Bundling::BundleLayer.new
    eventSent = false
    EventDispatcher.instance.subscribe(:bundleParsed) { |bundle| eventSent = true}
    EventDispatcher.instance.dispatch(:bundleData, StringIO.new(@inBundle), true, nil)
    assert(eventSent)
  end

  def test_short_bundles
    bl = Bundling::BundleLayer.new
    link = BDummyLink.new
    eventSent = false
    EventDispatcher.instance.subscribe(:bundleParsed) { |bundle| eventSent = true}

    sio = RdtnStringIO.new
    @inBundle.length.times do |i|
      sio.enqueue(@inBundle[i].chr)
      fin = (sio.length == @inBundle.length)
      EventDispatcher.instance.dispatch(:bundleData, sio, fin, link)
    end

    assert(eventSent, "The ':bundleParsed' event was not received.")
  end

  def test_fragmentation
    data = open(__FILE__) { |f| f.read }
    sender = "dtn:test"
    dest = "dtn:bubbler"
    maxSize = 100
    bundle = Bundling::Bundle.new(data, dest, sender)
    fragments = bundle.fragmentMaxSize(maxSize)
    assert(fragments.length > 1, "Expected more than one fragment")
    fragments.each do |fragment|
      assert(fragment.to_s.length <= maxSize, "Fragments must be smaller than #{maxSize} bytes")
      assert_equal(dest, fragment.destEid.to_s)
      assert_equal(sender, fragment.srcEid.to_s)
    end
    assembled = Bundling::Bundle.reassembleArray(fragments.reverse)
    assert_equal(bundle.to_s, assembled.to_s, "Reassembled bundle must equal the original")
  end

end

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

    assert(bundle.parserFinished?)
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

  def test_marshalling
    bundle = Bundling::Bundle.new("test", "dtn://test", "dtn://test")
    bundle.incomingLink = 42
    bundle.custodyAccepted = true
    bundle.forwardLog.addEntry(:incoming, :transmitted, "dtn://hugo")
    str    = Marshal.dump(bundle)
    b2     = Marshal.load(str)
    assert_equal(bundle.to_s, b2.to_s)
    assert_equal(bundle.forwardLog.getLatestEntry, b2.forwardLog.getLatestEntry)
    assert_nil(b2.incomingLink)
    assert(b2.custodyAccepted?)
  end

  def test_bundle_events
    Bundling::ParserManager.registerEvents
    eventSent = false
    EventDispatcher.instance.subscribe(:bundleParsed) { |bundle| eventSent = true}
    EventDispatcher.instance.dispatch(:bundleData, StringIO.new(@inBundle), nil)
    assert(eventSent)
  end

  def test_short_bundles
    Bundling::ParserManager.registerEvents
    link = BDummyLink.new
    eventSent = false
    EventDispatcher.instance.subscribe(:bundleParsed) { |bundle| eventSent = true}

    sio = RdtnStringIO.new
    @inBundle.length.times do |i|
      sio.enqueue(@inBundle[i].chr)
      fin = (sio.length == @inBundle.length)
      EventDispatcher.instance.dispatch(:bundleData, sio, link)
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

  def test_set_flags
    data = open(__FILE__) { |f| f.read }
    sender = "dtn:test"
    dest = "dtn:bubbler"
    bundle = Bundling::Bundle.new(data, dest, sender)
    bundle.fragment = true
    assert_equal(0b000000000000000000001, bundle.procFlags)
    assert(bundle.fragment?)
    bundle.administrative = true
    assert_equal(0b000000000000000000011, bundle.procFlags)
    assert(bundle.administrative?)
    bundle.dontFragment = true
    assert_equal(0b000000000000000000111, bundle.procFlags)
    assert(bundle.dontFragment?)
    bundle.requestCustody = true
    assert_equal(0b000000000000000001111, bundle.procFlags)
    assert(bundle.requestCustody?)
    bundle.destinationIsSingleton = true
    assert_equal(0b000000000000000011111, bundle.procFlags)
    assert(bundle.destinationIsSingleton?)
    bundle.requestApplicationAcknowledgement = true
    assert_equal(0b000000000000000111111, bundle.procFlags)
    assert(bundle.requestApplicationAcknowledgement?)

    bundle.priority = :bulk
    assert_equal(0b000000000000000111111, bundle.procFlags)
    assert_equal(:bulk, bundle.priority)
    bundle.priority = :normal
    assert_equal(0b000000000000010111111, bundle.procFlags)
    assert_equal(:normal, bundle.priority)
    bundle.priority = :expedited
    assert_equal(0b000000000000100111111, bundle.procFlags)
    assert_equal(:expedited, bundle.priority)

    bundle.receptionSrr = true
    assert_equal(0b000000100000100111111, bundle.procFlags)
    assert(bundle.receptionSrr?)
    bundle.custodyAcceptanceSrr = true
    assert_equal(0b000001100000100111111, bundle.procFlags)
    assert(bundle.custodyAcceptanceSrr?)
    bundle.forwardingSrr = true
    assert_equal(0b000011100000100111111, bundle.procFlags)
    assert(bundle.forwardingSrr?)
    bundle.deliverySrr = true
    assert_equal(0b000111100000100111111, bundle.procFlags)
    assert(bundle.deliverySrr?)
    bundle.deletionSrr = true
    assert_equal(0b001111100000100111111, bundle.procFlags)
    assert(bundle.deletionSrr?)

    bundle.deletionSrr = false
    assert_equal(0b000111100000100111111, bundle.procFlags)
    assert((not bundle.deletionSrr?))
    bundle.deliverySrr = false
    assert_equal(0b000011100000100111111, bundle.procFlags)
    assert((not bundle.deliverySrr?))
    bundle.forwardingSrr = false
    assert_equal(0b000001100000100111111, bundle.procFlags)
    assert((not bundle.forwardingSrr?))
    bundle.custodyAcceptanceSrr = false
    assert_equal(0b000000100000100111111, bundle.procFlags)
    assert((not bundle.custodyAcceptanceSrr?))
    bundle.receptionSrr = false
    assert_equal(0b000000000000100111111, bundle.procFlags)
    assert((not bundle.receptionSrr?))

    bundle.priority = :normal
    assert_equal(0b000000000000010111111, bundle.procFlags)
    assert_equal(:normal, bundle.priority)
    bundle.priority = :expedited
    assert_equal(0b000000000000100111111, bundle.procFlags)
    assert_equal(:expedited, bundle.priority)
    bundle.priority = :bulk
    assert_equal(0b000000000000000111111, bundle.procFlags)
    assert_equal(:bulk, bundle.priority)

    bundle.requestApplicationAcknowledgement = false
    assert_equal(0b000000000000000011111, bundle.procFlags)
    assert((not bundle.requestApplicationAcknowledgement?))
    bundle.destinationIsSingleton = false
    assert_equal(0b000000000000000001111, bundle.procFlags)
    assert((not bundle.destinationIsSingleton?))
    bundle.requestCustody = false
    assert_equal(0b000000000000000000111, bundle.procFlags)
    assert((not bundle.requestCustody?))
    bundle.dontFragment = false
    assert_equal(0b000000000000000000011, bundle.procFlags)
    assert((not bundle.dontFragment?))
    bundle.administrative = false
    assert_equal(0b000000000000000000001, bundle.procFlags)
    assert((not bundle.administrative?))
    bundle.fragment = false
    assert_equal(0b000000000000000000000, bundle.procFlags)
    assert((not bundle.fragment?))
  end

  def test_block_flags
    data = open(__FILE__) { |f| f.read }
    sender = "dtn:test"
    dest = "dtn:bubbler"
    bundle = Bundling::Bundle.new(data, dest, sender)
    block = Bundling::PayloadBlock.new(bundle)
    block.flags = 0

    block.replicateBlockForEveryFragment = true
    assert_equal(0b0000001, block.flags)
    assert(block.replicateBlockForEveryFragment?)
    block.transmitStatusIfBlockNotProcessed = true
    assert_equal(0b0000011, block.flags)
    assert(block.transmitStatusIfBlockNotProcessed?)
    block.deleteBundleIfBlockNotProcessed = true
    assert_equal(0b0000111, block.flags)
    assert(block.deleteBundleIfBlockNotProcessed?)
    block.lastBlock = true
    assert_equal(0b0001111, block.flags)
    assert(block.lastBlock?)
    block.discardBlockIfNotProcessed = true
    assert_equal(0b0011111, block.flags)
    assert(block.discardBlockIfNotProcessed?)
    block.forwardedBlockWithoutProcessing = true
    assert_equal(0b0111111, block.flags)
    assert(block.forwardedBlockWithoutProcessing?)
    block.containsEidReference = true
    assert_equal(0b1111111, block.flags)
    assert(block.containsEidReference?)

    block.containsEidReference = false
    assert_equal(0b0111111, block.flags)
    assert((not block.containsEidReference?))
    block.forwardedBlockWithoutProcessing = false
    assert_equal(0b0011111, block.flags)
    assert((not block.forwardedBlockWithoutProcessing?))
    block.discardBlockIfNotProcessed = false
    assert_equal(0b0001111, block.flags)
    assert((not block.discardBlockIfNotProcessed?))
    block.lastBlock = false
    assert_equal(0b0000111, block.flags)
    assert((not block.lastBlock?))
    block.deleteBundleIfBlockNotProcessed = false
    assert_equal(0b0000011, block.flags)
    assert((not block.deleteBundleIfBlockNotProcessed?))
    block.transmitStatusIfBlockNotProcessed = false
    assert_equal(0b0000001, block.flags)
    assert((not block.transmitStatusIfBlockNotProcessed?))
    block.replicateBlockForEveryFragment = false
    assert_equal(0b0000000, block.flags)
    assert((not block.replicateBlockForEveryFragment?))

  end

end

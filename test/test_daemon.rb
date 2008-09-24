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
require "daemon"
require "fileutils"

class TestDaemon < Test::Unit::TestCase

  def setup
    @daemon = RdtnDaemon::Daemon.new("dtn://receiver.dtn")
    #@router = RoutingTable.new(@daemon.config, @daemon.evDis, nil)
  end

  def test_loopback_data
    received = false
    payload  = "test"
    @daemon.register("recvtag") do |b|
      assert_equal(payload, b.payload)
      assert_equal("dtn://receiver.dtn/recvtag", b.destEid.to_s)
      assert_equal("dtn://receiver.dtn/sendtag", b.srcEid.to_s)
      received = true
    end
    @daemon.sendDataTo(payload, "dtn://receiver.dtn/recvtag", "sendtag")
    assert(received)
  end

  def test_loopback_bundle
    received = false
    bundle = Bundling::Bundle.new("test","dtn://receiver.dtn/recvtag")
    @daemon.register("recvtag") do |b|
      assert_equal(bundle.payload, b.payload)
      assert_equal("dtn://receiver.dtn/recvtag", b.destEid.to_s)
      received = true
    end
    @daemon.sendBundle(bundle)
    assert(received)
  end

  TESTCONF = <<END_OF_STRING
#storageDir 42, "store"
localEid "dtn://athird.dtn/"
END_OF_STRING

  def test_init
    assert_equal("dtn://receiver.dtn", @daemon.config.localEid.to_s)
    confFilename = "test.conf-#{Time.now.to_i.to_s}"
    ARGV.concat(["-c", confFilename, "-l", "dtn://another.eid"])
    @daemon.parseOptions
    assert_equal("dtn://another.eid", @daemon.config.localEid.to_s)

    open(confFilename, "w") {|f| f.write(TESTCONF)}
    @daemon.parseConfigFile
    # If the EID was set in the command line, the value must not be overridden
    # from the config file
    assert_equal("dtn://another.eid", @daemon.config.localEid.to_s)
    #assert_equal(42, @daemon.config.store.maxSize)
    #assert_equal("store", @daemon.config.store.storageDir)
    @daemon.config.localEid = nil

    @daemon.parseConfigFile
    assert_equal("dtn://athird.dtn/", @daemon.config.localEid.to_s)
    File.delete(confFilename)
  end

end

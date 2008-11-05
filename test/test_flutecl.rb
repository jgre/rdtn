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
require "rdtnevent"
require "flutecl"
require "bundle"


class TestFluteConvergenceLayer < Test::Unit::TestCase
  @@inDirname = File.expand_path("ppgin")
  @@outDirname = File.expand_path("ppgout")
  @@fn1, @@fn2 = "file1", "file2"
  @@file1 = "bla"
  @@file2 = "fasel"

  def setup
    @evDis  = EventDispatcher.new
    @config = RdtnConfig.new
    begin
      Dir.mkdir(@@inDirname)
      Dir.mkdir(@@outDirname)
    rescue
    end
    File.open(@@inDirname + "/" + @@fn1, "w") {|file| file << @@file1}
    File.open(@@inDirname + "/" + @@fn2, "w") {|file| file << @@file2}
  end

  def teardown
    begin
      File.delete(@@inDirname + "/" + @@fn1)
      File.delete(@@inDirname + "/" + @@fn2)
    rescue
    end
    Dir.delete(@@inDirname)

    Dir.foreach(@@outDirname) do |filename|
      compl = @@outDirname + "/" + filename
      unless File.directory?(compl)
	File.delete(compl)
      end
    end
    Dir.delete(@@outDirname)
  end

  def test_receiver
    fluteIF = FluteCL::FluteInterface.new(@config, @evDis, "flute0", 
					  :directory => @@inDirname,
					  :interval => 1)

    counter = 0
    @evDis.subscribe(:bundleData) do |queue, cl|
      outBundle = queue.read
      rdebug("Received bundle: #{outBundle}")
      assert((outBundle == @@file1 or outBundle == @@file2), "Bundle must equal one of the test files")
      counter += 1
    end
    sleep(2)
    fluteIF.close

    assert_equal(2, counter)
    assert_equal(2, Dir.entries(@@inDirname).length, 
	"Directory must be empty (can only contain '.' and '..')")
  end

  def test_sender
    createReceived = closedReceived = false
    srcEid = "dtn://test/bla"
    destEid = "dtn://oink/grunt"
    @config.localEid = "dtn://bla.fasel"
    bundle = Bundling::Bundle.new("mypayload", destEid, srcEid)

    @evDis.subscribe(:linkOpen) do |cl|
      createReceived = true 
      cl.sendBundle(bundle)
      cl.close()
    end

    @evDis.subscribe(:linkClosed) do |cl|
      closedReceived= true 
    end

    fluteLink = FluteCL::FluteLink.new(@config, @evDis, @@outDirname)
    #sleep(2)
    #fluteLink.close
    assert(createReceived, "Create Event was not received for the FLUTE link")
    assert(closedReceived, "Closed Event was not received for the FLUTE link")

    assert(File.exist?(@@outDirname + "/#{bundle.object_id}.meta"), 
	   "Metadata file was not created")
    assert(File.exist?(@@outDirname + "/#{bundle.object_id}.bundle"), 
	   "Bundle file was not created")
    File.open(@@outDirname + "/#{bundle.object_id}.bundle") do |file|
      data = file.read
      serialized_bundle = bundle.to_s
      if data.respond_to?(:force_encoding)
	data.force_encoding('UTF-8')
	serialized_bundle.force_encoding('UTF-8')
      end
      assert_equal(serialized_bundle, data)
    end
    #FIXME: test contents of metadata file
    #File.open(@@outDirname + "/#{bundle.object_id}.meta") do |file|
    #  puts file.read
    #end

  end

end

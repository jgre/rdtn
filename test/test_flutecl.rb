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
require "event-loop/timer"

require "rdtnlog"
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

    EventLoop.current = EventLoop.new
    Dir.mkdir(@@inDirname)
    begin
    Dir.mkdir(@@outDirname)
    rescue
    end
    File.open(@@inDirname + "/" + @@fn1, "w") {|file| file << @@file1}
    File.open(@@inDirname + "/" + @@fn2, "w") {|file| file << @@file2}
  end

  def teardown
    EventDispatcher.instance.clear
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
    fluteIF = FluteCL::FluteInterface.new("flute0", :directory => @@inDirname,
					  :interval => 1)

    counter = 0
    EventDispatcher.instance().subscribe(:bundleData) do |queue, fin, cl|
      outBundle = queue.read
      RdtnLogger.instance.debug("Received bundle: #{outBundle}")
      assert((outBundle == @@file1 or outBundle == @@file2), "Bundle must equal one of the test files")
      counter += 1
    end
    2.seconds.from_now { EventLoop.quit()}
    
    EventLoop.run

    assert_equal(2, counter)
    assert_equal(2, Dir.entries(@@inDirname).length, 
	"Directory must be empty (can only contain '.' and '..')")
  end

  def test_sender
    fluteLink = FluteCL::FluteLink.new(@@outDirname)
    createReceived = closedReceived = false
    srcEid = "dtn://test/bla"
    destEid = "dtn://oink/grunt"
    RdtnConfig::Settings.instance.localEid = "dtn://bla.fasel"
    bundle = Bundling::Bundle.new("mypayload", destEid, srcEid)
    bundle.cosFlags = 1

    EventDispatcher.instance().subscribe(:linkCreated) do |cl|
      createReceived = true 
      fluteLink.sendBundle(bundle)
      fluteLink.close()
    end

    EventDispatcher.instance().subscribe(:linkClosed) do |cl|
      closedReceived= true 
    end

    2.seconds.from_now {EventLoop.quit()}
    EventLoop.run()

    assert(createReceived, "Create Event was not received for the FLUTE link")
    assert(closedReceived, "Closed Event was not received for the FLUTE link")

    assert(File.exist?(@@outDirname + "/#{bundle.object_id}.meta"), 
	   "Metadata file was not created")
    assert(File.exist?(@@outDirname + "/#{bundle.object_id}.bundle"), 
	   "Bundle file was not created")
    File.open(@@outDirname + "/#{bundle.object_id}.bundle") do |file|
      data = file.read
      assert_equal(bundle.to_s, data)
    end
    #FIXME: test contents of metadata file
    File.open(@@outDirname + "/#{bundle.object_id}.meta") do |file|
      puts file.read
    end

  end

end

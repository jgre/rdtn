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

require "bundle"
require "test/unit"
require "rdtnevent"
require "tcpcl"


class TestTCPConvergenceLayer < Test::Unit::TestCase


  def test_contact_exchange
    @config.localEid = "dtn://bla.fasel"
    
    rdebug(self, "starting contact exchange")
    
    @interface=TCPCL::TCPInterface.new(@config, @evDis, "tcp0", 
				       :host=> "localhost", :port => 3456)
    @link=TCPCL::TCPLink.new(@config, @evDis)
    @link.open("link1", :host => "localhost", :port => 3456)

    sleep(2)
    @interface.close
    @link.close
    
    assert_equal(@config.localEid.to_s, @link.remoteEid.to_s)

  end

  def test_bundle_sending
    @config.localEid = "dtn://bla.fasel"
    
    rdebug(self, "starting contact exchange")
    
    inBundle = "I'm a DTN bundle01!"
    begin
      inBundle = open(File.join(File.dirname(__FILE__), "mbfile")) do |f|
	f.read
      end
    rescue
      rwarn(self, "Could not open large testfile")
    end
    outBundle = ""
    handler = @evDis.subscribe(:bundleData) do |queue, cl|
      oldLen = outBundle.length
      outBundle += queue.read
      rdebug(self, "Received bundle1: #{outBundle.length-oldLen}")
    end
    interface=TCPCL::TCPInterface.new(@config, @evDis, "tcp0", 
				      :host => "localhost", :port => 3456)
    link=TCPCL::TCPLink.new(@config, @evDis)
    link.open("link1", :host => "localhost", :port => 3456)

    bundleSent = false
    mon = Monitor.new
    @evDis.subscribe(:linkOpen) do |link|
      mon.synchronize do
	link.sendBundle(inBundle) unless bundleSent
	bundleSent = true
      end
    end
    sleep(2)
    link.close
    interface.close
    
    assert_equal(@config.localEid.to_s, link.remoteEid.to_s)
    assert_equal(inBundle.length, outBundle.length)
    
    assert_equal(true, link.connection[:acks])
    interface.links.each do |link|
       assert_equal(true, link.connection[:acks])
    end

  end

  # Test negotiation of ack flags: true/false -> dont use acks
 
  def test_bundle_sending2
    @config.localEid = "dtn://bla.fasel"
    
    rdebug(self, "starting contact exchange")
    
    inBundle = "I'm a DTN bundle!"
    outBundle = "" 
    handler = @evDis.subscribe(:bundleData) do |queue, cl|
      outBundle += queue.read 
      rdebug(self, "Received bundle2: #{outBundle}")
    end
    
    interface=TCPCL::TCPInterface.new(@config, @evDis, "tcp0", 
				      :host => "localhost", :port => 3456)
    link=TCPCL::TCPLink.new(@config, @evDis)
    
    link.options[:acks] = false
    
    link.open("link1", :host => "localhost", :port => 3456)
    
    bundleSent = false
    mon = Monitor.new
    @evDis.subscribe(:linkOpen) do |link|
      mon.synchronize do
	link.sendBundle(inBundle) unless bundleSent
	bundleSent = true
      end
    end
    sleep(2)
    link.close
    interface.close
    
    @evDis.unsubscribe(:bundleData, handler)

    assert_equal(@config.localEid.to_s, link.remoteEid.to_s)
    assert_equal(inBundle, outBundle)
  
    assert_equal(false, link.connection[:acks])
    interface.links.each do |link|
       assert_equal(false, link.connection[:acks])
    end

  end

  def setup
    @evDis  = EventDispatcher.new
    @config = RdtnConfig::Settings.new(@evDis)
  end

end

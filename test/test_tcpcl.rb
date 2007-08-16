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
# $Id: fileup.py 8 2006-12-22 20:00:21Z jgre $

$:.unshift File.join(File.dirname(__FILE__), "..", "lib")

require "test/unit"
require "rdtnlog"
require "rdtnevent"
require "tcpcl"


class TestTCPConvergenceLayer < Test::Unit::TestCase


  def test_contact_exchange
    RdtnConfig::Settings.instance.localEid = "dtn://bla.fasel"
    log=RdtnLogger.instance()
    
    log.debug("starting contact exchange")
    
    @interface=TCPCL::TCPInterface.new("tcp0", :host=> "localhost", :port => 3456)
    @link=TCPCL::TCPLink.new
    @link.open("link1", :host => "localhost", :port => 3456)

    sleep(2)
    @interface.close
    @link.close
    
    assert_equal(RdtnConfig::Settings.instance.localEid.to_s, @link.remoteEid.to_s)

  end

  def test_bundle_sending
    RdtnConfig::Settings.instance.localEid = "dtn://bla.fasel"
    log=RdtnLogger.instance()
    
    log.debug("starting contact exchange")
    
    inBundle = "I'm a DTN bundle01!"
    begin
      inBundle = open(File.join(File.dirname(__FILE__), "mbfile")) do |f|
	f.read
      end
    rescue
      RdtnLogger.instance.warn("Could not open large testfile")
    end
    outBundle = ""
    handler = EventDispatcher.instance().subscribe(:bundleData) do |queue, fin, cl|
      oldLen = outBundle.length
      outBundle += queue.read
      log.debug("Received bundle1: #{outBundle.length-oldLen}")
    end
    interface=TCPCL::TCPInterface.new("tcp0", :host => "localhost", :port => 3456)
    link=TCPCL::TCPLink.new
    link.open("link1", :host => "localhost", :port => 3456)

    bundleSent = false
    mon = Monitor.new
    EventDispatcher.instance.subscribe(:routeAvailable) do |link, dest|
      mon.synchronize do
	link.sendBundle(inBundle) unless bundleSent
	bundleSent = true
      end
    end
    sleep(2)
    link.close
    interface.close
    
    assert_equal(RdtnConfig::Settings.instance.localEid.to_s, link.remoteEid.to_s)
    assert_equal(inBundle.length, outBundle.length)
    
    assert_equal(true, link.connection[:acks])
    interface.links.each do |link|
       assert_equal(true, link.connection[:acks])
    end

  end

  # Test negotiation of ack flags: true/false -> dont use acks
 
  def test_bundle_sending2
    log=RdtnLogger.instance()
    
    RdtnConfig::Settings.instance.localEid = "dtn://bla.fasel"
    
    log.debug("starting contact exchange")
    
    inBundle = "I'm a DTN bundle!"
    outBundle = "" 
    handler = EventDispatcher.instance().subscribe(:bundleData) do |queue, fin, cl|
      outBundle += queue.read 
      log.debug("Received bundle2: #{outBundle}")
    end
    
    interface=TCPCL::TCPInterface.new("tcp0", :host => "localhost", :port => 3456)
    link=TCPCL::TCPLink.new
    
    link.options[:acks] = false
    
    link.open("link1", :host => "localhost", :port => 3456)
    
    bundleSent = false
    mon = Monitor.new
    EventDispatcher.instance.subscribe(:routeAvailable) do |link, dest|
      mon.synchronize do
	link.sendBundle(inBundle) unless bundleSent
	bundleSent = true
      end
    end
    sleep(2)
    link.close
    interface.close
    
    EventDispatcher.instance().unsubscribe(:bundleData, handler)

    assert_equal(RdtnConfig::Settings.instance.localEid.to_s, link.remoteEid.to_s)
    assert_equal(inBundle, outBundle)
  
    assert_equal(false, link.connection[:acks])
    interface.links.each do |link|
       assert_equal(false, link.connection[:acks])
    end

  end

  def setup
    RdtnLogger.instance.level = Logger::WARN
  end

  def teardown
    EventDispatcher.instance.clear
    ObjectSpace.each_object(Link) {|link| link.close}
    ObjectSpace.each_object(Interface) {|iface| iface.close}
  end
end

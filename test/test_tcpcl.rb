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
require "event-loop/timer"

require "rdtnlog"
require "rdtnevent"
require "tcpcl"


class TestTCPConvergenceLayer < Test::Unit::TestCase


  def test_contact_exchange
    RdtnConfig::Settings.instance.localEid = "dtn://bla.fasel"
    log=RdtnLogger.instance()
    log.level=Logger::INFO
    
    log.debug("starting contact exchange")
    
    @interface=TCPCL::TCPInterface.new("tcp0", :host=> "localhost", :port => 3456)
    @link=TCPCL::TCPLink.new
    @link.open("link1", :host => "localhost", :port => 3456)

    2.seconds.from_now { EventLoop.quit()}
    
    EventLoop.run()
    
    assert_equal(RdtnConfig::Settings.instance.localEid.to_s, @link.remoteEid.to_s)

  end

  def test_bundle_sending
    RdtnConfig::Settings.instance.localEid = "dtn://bla.fasel"
    log=RdtnLogger.instance()
    log.level=Logger::DEBUG
    
    log.debug("starting contact exchange")
    
    inBundle = "I'm a DTN bundle!"
    outBundle = ""
    handler = EventDispatcher.instance().subscribe(:bundleData) do |queue, fin, cl|
      outBundle += queue.read
      log.debug("Received bundle1: #{outBundle}")
    end
    interface=TCPCL::TCPInterface.new("tcp0", :host => "localhost", :port => 3456)
    link=TCPCL::TCPLink.new
    link.open("link1", :host => "localhost", :port => 3456)

    1.seconds.from_now { link.sendBundle(inBundle) }
    3.seconds.from_now { EventLoop.quit()}
    
    EventLoop.run()
    
    EventDispatcher.instance().unsubscribe(:bundleData, handler)

    assert_equal(RdtnConfig::Settings.instance.localEid.to_s, link.remoteEid.to_s)
    assert_equal(inBundle, outBundle)
    
    assert_equal(true, link.connection[:acks])
    interface.links.each do |link|
       assert_equal(true, link.connection[:acks])
    end

  end

  # Test negotiation of ack flags: true/false -> dont use acks
 
  def test_bundle_sending2
    log=RdtnLogger.instance()
    log.level=Logger::DEBUG
    
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
    
    1.seconds.from_now { link.sendBundle(inBundle) }
    3.seconds.from_now { EventLoop.quit()}
    
    EventLoop.run()
  
    EventDispatcher.instance().unsubscribe(:bundleData, handler)

    assert_equal(RdtnConfig::Settings.instance.localEid.to_s, link.remoteEid.to_s)
    assert_equal(inBundle, outBundle)
  
    assert_equal(false, link.connection[:acks])
    interface.links.each do |link|
       assert_equal(false, link.connection[:acks])
    end

  end

  def test_too_short
    contact_hdr = "dtn!\003\000\000x\017dtn://bla.fasel"

    RdtnConfig::Settings.instance.localEid = "dtn://bla.fasel"
    log=RdtnLogger.instance()
    log.level=Logger::INFO
    
    log.debug("starting contact exchange")
    
    @interface=TCPCL::TCPInterface.new("tcp0", :host => "localhost", :port => 3456)
    s = TCPSocket.new("localhost", 3456)

    i = 1
    contact_hdr.each_byte do |byte|
      i.seconds.from_now { s.send(byte.chr, 0) }
      i += 1
    end

    (contact_hdr.length+1).seconds.from_now { EventLoop.quit()}

    contactEid = ""
    EventDispatcher.instance().subscribe(:contactEstablished) do |link|
      contactEid = link.remoteEid
    end
    
    EventLoop.run()
    
    assert_equal(RdtnConfig::Settings.instance.localEid.to_s, contactEid.to_s)

  end

  def setup
  end

  def teardown
    ObjectSpace.each_object(Link) {|link| link.close}
    ObjectSpace.each_object(Interface) {|iface| iface.close}
  end
end

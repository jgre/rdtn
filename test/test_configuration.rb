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
require "configuration"

class TestConfiguration < Test::Unit::TestCase

  CLs = [:tcp, :udp, :flute, :client]

  def setup
    @evDis  = EventDispatcher.new
    @config = RdtnConfig::Settings.new(@evDis)
  end

  def teardown
  end

  def test_load
  end

  def test_add_interface
    conf = RdtnConfig::Reader.new(@config, @evDis)
    CLs.each_with_index {|cl, i| conf.interface(:add, cl, "if#{i}")}
  end

  def test_remove_interface
  end

  def test_add_link
    conf = RdtnConfig::Reader.new(@config, @evDis)
    tcpOK = udpOK = fluteOK = false
    @evDis.subscribe(:linkCreated) do |link|
      case link.class.name
      when "TCPCL::TCPLink":     tcpOK   = true
      when "UDPCL::UDPLink":     udpOK   = true
      when "FluteCL::FluteLink": fluteOK = true
      end
    end
    CLs.each_with_index {|cl, i| conf.link(:add, cl, "link#{i}", :policy => :onDemand) unless cl == :client}
    assert(tcpOK)
    assert(udpOK)
    assert(fluteOK)
  end

  def test_remove_link
  end

  def test_add_route
    eventSent = false
    @evDis.subscribe(:routeAvailable) do |*args|
      eventSent = true
    end
    conf = RdtnConfig::Reader.new(@config, @evDis)
    conf.route(:add, "test", "someLink")
    assert(eventSent)
  end

  def test_remove_route
  end

end

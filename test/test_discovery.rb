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
require "discovery"
require "tcpcl"
require "udpcl"

class TestDiscovery < Test::Unit::TestCase

  def setup
    @evDis  = EventDispatcher.new
    @config = RdtnConfig::Settings.new
    @tcpif = TCPCL::TCPInterface.new(@config, @evDis, "testtcpif", 
				     :port => 4558)
    @udpif = UDPCL::UDPInterface.new(@config, @evDis, "testudpif", 
				     :port => 4558)
  end

  def teardown
    @tcpif.close
    @udpif.close
  end

  def test_ipdiscovery
    discSender = IPDiscovery.new(@config, @evDis, "224.224.1.1", 12345, 1, 
				 [@tcpif, @udpif])
    discRecv   = IPDiscovery.new(@config, @evDis, "224.224.1.1", 12345)
    tcpEventCount = udpEventCount = 0
    @evDis.subscribe(:opportunityAvailable) do |tp, opts, eid|
      case tp
      when :tcp 
	tcpEventCount += 1
	assert_equal(@tcpif.host, opts[:host])
	assert_equal(@tcpif.port, opts[:port])
      when :udp
	udpEventCount += 1
	assert_equal(@udpif.host, opts[:host])
	assert_equal(@udpif.port, opts[:port])
      else flunk("Invalid CL type #{tp}")
      end
    end

    discRecv.start
    discSender.start
    sleep(2)

    assert_equal(1, tcpEventCount)
    assert_equal(1, udpEventCount)

  end

end

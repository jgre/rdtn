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
require "udpcl"
require "configuration"
require "platform"

class TestUDPConvergenceLayer < Test::Unit::TestCase

  @platform = RdtnPlatform.new
  
  def setup
    @evDis  = EventDispatcher.new
    @config = RdtnConfig::Settings.new
  end

  def test_bundle_sending
    @config.localEid = "dtn://bla.fasel"
    
    rdebug(self, "starting contact exchange")
    
    inBundle = "I'm a DTN bundle!"
    begin
      inBundle = open(File.join(File.dirname(__FILE__), "mbfile")) do |f|
	f.read(@platform.udpmaxdgram)
      end
    rescue
    end
    outBundle = ""
    handler = @evDis.subscribe(:bundleData) do |queue, cl|
      outBundle += queue.read
      rdebug(self, "Received bundle1: #{outBundle}")
    end
    interface=UDPCL::UDPInterface.new(@config, @evDis, "udp0", 
				      :host => "localhost", :port => 3456)
    link=UDPCL::UDPLink.new(@config, @evDis)
    link.open("link1", :host => "localhost", :port => 3456)

    link.sendBundle(inBundle)
    sleep(3)
    link.close
    interface.close
    
    assert_equal(inBundle, outBundle)
    
  end

end

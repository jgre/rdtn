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
$:.unshift File.join(File.dirname(__FILE__), "..", "sim")

require "test/unit"
require "rubygems"
require "shoulda"
require "graph"
require "core"
require "fileutils"

class TestSim < Test::Unit::TestCase

  def setup
    @g = Sim::Graph.new
    @g.edge 1=>2
    @g.edge 2=>3, :start=>10, :end=>15
    @g.edge 3=>4

    @sim        = Sim::Core.new
    @sim.events = @g.events
    @sim.createNodes(@g.nodes.length)
  end

  def test_transmit
    received = false
    data     = "test"
    t0       = Time.now.to_i
    @sim.nodes[3].register do |bundle|
      received = true
      assert_equal(data, bundle.payload)
      assert_equal("dtn://kasuari2/", bundle.srcEid.to_s)
      assert_operator(t0+10, :<=, RdtnTime.now.to_i)
    end
    @sim.at(1) do |t|
      assert_equal(1, t)
      @sim.nodes[2].sendDataTo(data, "dtn://kasuari3/")
      false
    end
    @sim.run
    assert(received)
  end

  should 'allow routers to be configured globally' do
    @sim.nodes.each_value {|node| assert node.router.is_a?(RoutingTable)}
    @sim.nodes.router :epidemic
    @sim.nodes.each_value {|node| assert node.router.is_a?(EpidemicRouter)}
  end

  should 'allow link capacities to be configured globally' do
    @sim.nodes.linkCapacity = 1
    @g = Sim::Graph.new
    @g.edge 1=>2

    event = false
    @sim.node(1).evDis.subscribe(:linkOpen) do |link|
      event = true
      assert_equal 1, link.bytesPerSec
    end
    @sim.events = @g.events
    @sim.run
    assert event
  end

end

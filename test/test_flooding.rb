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
require "graph"
require "core"
require "fileutils"

class TestFlooding < Test::Unit::TestCase

  def setup
    @g = Sim::Graph.new
    @dirName    = File.join(Dir.getwd, "test#{Time.now.to_i}")
    @sim        = Sim::SimCore.new(@dirName)
  end

  def teardown
    FileUtils.rm_rf(@dirName)
  end

  def simple_graph
    @g.edge 1=>2
    @g.edge 2=>3, :start=>1
    @g.edge 2=>4, :start=>1
    @g.edge 2=>6
    @g.edge 4=>5
    @g.edge 4=>6
    @sim.events = @g.events
    @sim.createNodes(@g.nodes.length)
    @sim.nodes.each_value do |node|
      node.router(:priorityRouter)
    end
  end

  def test_simple_graph_broadcast
    simple_graph
    receivedBy = []
    data       = "test"
    eid        = "dtn:all"
    @sim.nodes.each do |id, node|
      node.register(eid) {|b| receivedBy.push(id)}
    end
    @sim.nodes[1].sendDataTo(data, eid)
    @sim.run
    assert_equal(@sim.nodes.length, receivedBy.length)
    assert_equal(receivedBy, receivedBy.uniq)
  end

  def test_simple_graph_unicast
    simple_graph
    receivedBy = []
    data       = "test"
    eid        = "dtn://kasuari6/"
    @sim.nodes.each do |id, node|
      node.register(eid) {|b| receivedBy.push(id)}
    end
    bundle = Bundling::Bundle.new(data, eid)
    bundle.destinationIsSingleton = true
    @sim.nodes[1].sendBundle(bundle)
    @sim.run
    @sim.nodes[1].config.setLogLevel(nil, Logger::ERROR)
    assert_equal([1, 2, 6], receivedBy)
  end

end

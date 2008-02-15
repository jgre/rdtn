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
$:.unshift File.join(File.dirname(__FILE__), "..", "apps", "stateval")

require "test/unit"
require "graph"
require "dijkstra"

class TestDijkstra < Test::Unit::TestCase

  def setup
    @g = Sim::Graph.new
    @g.addEdge(1, 2, 28, 30)
    @g.addEdge(1, 3, 2, 10)
    @g.addEdge(1, 5, 1, 6)
    @g.addEdge(2, 4, 9, 50)
    @g.addEdge(2, 6, 10, 50)
    @g.addEdge(3, 6, 24, 50)
    @g.addEdge(3, 8, 27, 50)
    @g.addEdge(4, 5, 5, 50)
    @g.addEdge(4, 7, 8, 50)
    @g.addEdge(4, 8, 7, 50)
    @g.addEdge(5, 2, 8, 9)
    @g.addEdge(5, 6, 26, 50)
    @g.addEdge(6, 7, 8, 50)
    @g.addEdge(6, 8, 1, 50)
    @g.addEdge(7, 8, 7, 50)

    open("graph.dot", "w") {|f| @g.printGraphviz(f)}

  end

  def test_values
    distVec, path = dijkstra(@g, 1, 0)
    assert_equal(0, distVec[1])
    assert_equal([1], path[1])
    assert_equal(8, distVec[2])
    assert_equal([1, 5, 2], path[2])
    assert_equal(2, distVec[3])
    assert_equal([1, 3], path[3])
    assert_equal(9, distVec[4])
    assert_equal([1, 5, 2, 4], path[4])
    assert_equal(1, distVec[5])
    assert_equal([1, 5], path[5])
    assert_equal(10, distVec[6])
    assert_equal([1, 5, 2, 6], path[6])
    assert_equal(9, distVec[7])
    assert_equal([1, 5, 2, 4, 7], path[7])
    assert_equal(9, distVec[8])
    assert_equal([1, 5, 2, 4, 8], path[8])
  end

  def test_time
    distVec, paths = dijkstra(@g, 1, 7)
    assert_equal(0, distVec[1])
    assert_equal(21, distVec[2])
    assert_equal(0, distVec[3])
    assert_equal(21, distVec[4])
    assert_equal(21, distVec[5])
    assert_equal(17, distVec[6])
    assert_equal(17, distVec[7])
    assert_equal(17, distVec[8])
  end

  #def test_symmetry
  #  @g.addEdge(2, 1, 28, 30)
  #  @g.addEdge(3, 1, 2, 10)
  #  @g.addEdge(5, 1, 1, 6)
  #  @g.addEdge(4, 2, 9, 15)
  #  @g.addEdge(6, 2, 10, 50)
  #  @g.addEdge(6, 3, 24, 50)
  #  @g.addEdge(8, 3, 27, 50)
  #  @g.addEdge(5, 4, 5, 50)
  #  @g.addEdge(7, 4, 8, 50)
  #  @g.addEdge(8, 4, 7, 50)
  #  @g.addEdge(2, 5, 8, 50)
  #  @g.addEdge(6, 5, 26, 50)
  #  @g.addEdge(7, 6, 8, 50)
  #  @g.addEdge(8, 6, 1, 50)
  #  @g.addEdge(8, 7, 7, 50)

  #  1.upto(8) do |node1|
  #    distVec1, path1 = dijkstra(@g, node1, 0)
  #    1.upto(8) do |node2|
  #      distVec2, path2 = dijkstra(@g, node2, 0)
  #      assert_equal(distVec1[node2], distVec2[node1])
  #      assert_equal(path1[node2], path2[node1].reverse)
  #    end
  #  end
  #end

  def test_isolated
    distVec, path = dijkstra(@g, 8, 0)
    assert_equal({8 => 0}, distVec)
  end
  
  def test_unreachable
    distVec, path = dijkstra(@g, 5, 0)
    assert_nil(distVec[1])
    assert(path[1].empty?)
    assert_nil(distVec[3])
    assert(path[3].empty?)

    assert_equal(8, distVec[2])
    assert_equal([5, 2], path[2])
    assert_equal(9, distVec[4])
    assert_equal([5, 2, 4], path[4])
    assert_equal(0, distVec[5])
    assert_equal([5], path[5])
    assert_equal(10, distVec[6])
    assert_equal([5, 2, 6], path[6])
    assert_equal(9, distVec[7])
    assert_equal([5, 2, 4, 7], path[7])
    assert_equal(9, distVec[8])
    assert_equal([5, 2, 4, 8], path[8])
  end

  def test_unreachable_time
    distVec, path = dijkstra(@g, 5, 10)
    assert_nil(distVec[1])
    assert(path[1].empty?)
    assert_nil(distVec[2])
    assert(path[2].empty?)
    assert_nil(distVec[3])
    assert(path[3].empty?)
    assert_nil(distVec[4])
    assert(path[4].empty?)

    assert_equal(0, distVec[5])
    assert_equal([5], path[5])
    assert_equal(16, distVec[6])
    assert_equal([5, 6], path[6])
    assert_equal(16, distVec[7])
    assert_equal([5, 6, 7], path[7])
    assert_equal(16, distVec[8])
    assert_equal([5, 6, 8], path[8])
  end

end

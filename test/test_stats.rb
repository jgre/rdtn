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
$:.unshift File.join(File.dirname(__FILE__), "..", "apps", "stateval")

require "test/unit"
require "eval2"
require "eventqueue"
require "dijkstra"

class TestStats < Test::Unit::TestCase

  def setup
    @model = NetworkModel.new
    evQ = Sim::EventQueue.new
    evQ.addEvent(1, 1, 2, :simConnection)
    evQ.addEvent(1, 3, 4, :simConnection)
    evQ.addEvent(5, 1, 3, :simConnection)
    evQ.addEvent(6, 3, 4, :simDisconnection)
    evQ.addEvent(10, 1, 2, :simDisconnection)
    evQ.addEvent(10, 1, 3, :simDisconnection)
    evQ.addEvent(14, 1, 3, :simConnection)
    evQ.addEvent(15, 2, 4, :simConnection)
    evQ.addEvent(16, 1, 2, :simConnection)
    evQ.addEvent(16, 1, 3, :simDisconnection)
    evQ.addEvent(19, 3, 4, :simConnection)
    evQ.addEvent(20, 1, 2, :simDisconnection)
    evQ.addEvent(20, 2, 4, :simDisconnection)
    evQ.addEvent(20, 3, 4, :simDisconnection)
    EventQueueParser.new(evQ, @model).parse

  end

  def test_global_stats
    assert_equal(7, @model.numberOfContacts)
    assert_equal(4, @model.uniqueContacts)
    assert_equal(4.42857142857143.to_s, @model.averageContactDuration.to_s)
    assert_equal(0, @model.numberOfBundles)
    assert_equal(0, @model.numberOfSubscribedBundles)
    assert_equal(0, @model.numberOfDeliveredBundles)
    assert_equal(0, @model.numberOfReplicas)
    assert_equal(0, @model.replicasPerBundle)
    assert_equal(0, @model.numberOfTransmissions)
    assert_equal(0, @model.transmissionsPerBundle)
    assert_equal(0, @model.averageDelay)
    assert_equal(0, @model.numberOfControlBundles)
  end

  def test_bundle_bundles
    @model.sink(1, 4)
    @model.sink(2, 3)
    b1 = StatBundle.new(1, 1, 42, 10, [4])
    b7 = StatBundle.new(1, 1, 7, 15, [4])
    b17 = StatBundle.new(2, 1, 77, 20, [3])
    @model.bundleEvent(1, nil, :in, b1, 1)
    @model.bundleEvent(1, 2, :out, b1, 1)
    @model.bundleEvent(2, 1, :in, b1, 1)
    @model.bundleEvent(1, 3, :out, b1, 5)
    @model.bundleEvent(3, 1, :in, b1, 5)
    @model.bundleEvent(3, 4, :out, b1, 5)
    @model.bundleEvent(4, 3, :in, b1, 5)
    @model.bundleEvent(2, 4, :out, b1, 15)
    @model.bundleEvent(4, 2, :in, b1, 15)

    @model.bundleEvent(1, nil, :in, b7, 7)
    @model.bundleEvent(1, 2, :out, b7, 7)
    @model.bundleEvent(2, 1, :in, b7, 7)
    @model.bundleEvent(1, 3, :out, b7, 14)
    @model.bundleEvent(3, 1, :in, b7, 14)
    @model.bundleEvent(3, 4, :out, b7, 19)
    @model.bundleEvent(4, 3, :in, b7, 19)
    @model.bundleEvent(2, 4, :out, b7, 15)
    @model.bundleEvent(4, 2, :in, b7, 15)

    @model.bundleEvent(1, nil, :in, b17, 17)
    @model.bundleEvent(1, 2, :out, b17, 17)
    @model.bundleEvent(2, 1, :in, b17, 17)
    @model.bundleEvent(2, 4, :out, b17, 17)
    @model.bundleEvent(4, 2, :in, b17, 17)
    @model.bundleEvent(4, 3, :out, b17, 19)
    @model.bundleEvent(3, 4, :in, b17, 19)

    assert_equal(3, @model.numberOfBundles)
    assert_equal(3, @model.numberOfSubscribedBundles)
    assert_equal(3, @model.numberOfDeliveredBundles)
    assert_equal(12, @model.numberOfReplicas)
    assert_equal(4, @model.replicasPerBundle)
    assert_equal(11, @model.numberOfTransmissions)
    assert_equal(3.66666666666667.to_s, @model.transmissionsPerBundle.to_s)
    assert_equal([[42, [4]], [7, [8]], [77, [2]]].sort, @model.annotatedDelays.sort)
    assert_equal([4, 8, 2].sort, @model.delays.sort)
    assert_equal(4.66666666666667.to_s, @model.averageDelay.to_s)
  end

  def test_paths
    distVec1, path1   = dijkstra(@model, 1, 1)
    distVec7, path7   = dijkstra(@model, 1, 7)
    distVec17, path17 = dijkstra(@model, 1, 17)
    distVec21, path21 = dijkstra(@model, 1, 21)

    assert_equal({1=>0,2=>0,3=>4,4=>4}, distVec1)
    assert_equal({1=>[1], 2=>[1, 2], 3=>[1, 3], 4=>[1, 3, 4]}, path1)

    assert_equal({1=>0,2=>0,3=>0,4=>8}, distVec7)
    assert_equal({1=>[1], 2=>[1, 2], 3=>[1, 3], 4=>[1, 2, 4]}, path7)

    assert_equal({1=>0,2=>0,3=>2,4=>0}, distVec17)
    assert_equal({1=>[1], 2=>[1, 2], 3=>[1, 2, 4, 3], 4=>[1, 2, 4]}, path17)

    assert_equal({1=>0}, distVec21)
    assert_equal({1=>[1]}, path21)
  end

  def test_network_analysis
    dv, path = dijkstra(@model, 2, 0)
    #p dv, path
    assert_equal(12, @model.numberOfTheoreticalPaths)
    assert_equal(1.66666666666667.to_s, @model.averageTheoreticalHopCount.to_s)
    assert_equal(3.66666666666667.to_s, @model.averageTheoreticalDelay.to_s)
  end

  def test_clustering_coefficient
    assert_equal(0, @model.totalClusteringCoefficient)
  end

end

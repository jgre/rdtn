$:.unshift File.join(File.dirname(__FILE__), '../../sim/maidenvoyage')

require 'maidenvoyage'
require 'graph'

class TestStress < Test::Unit::TestCase

  simulation_context 'Under stress the simulator' do

    network  :two_connected_nodes
    workload :sending_many_bundles

    should 'generate 1200 bundles' do
      assert_equal 1200, traffic_model.numberOfBundles
    end

    should 'deliver all bundles' do
      assert_equal 1, traffic_model.deliveryRatio
    end

  end

  simulation_context 'When contacts are too short, the simulator' do

    prepare do
      g = Sim::Graph.new
      g.edge 1 => 2, :start=>1, :end=>2
      sim.events = g.events
      sim.at(1) {sim.node(1).sendDataTo 'a'*2048, 'dtn://kasuari2/'; false}
    end

    should 'not deliver the bundle' do
      assert_equal 0, traffic_model.deliveryRatio
    end

  end

  simulation_context 'When one contact is too short, but a subsequent contact is sufficient, the simulator' do

    prepare do
      g = Sim::Graph.new
      g.edge 1 => 2, :start=>1, :end=>2
      g.edge 1 => 2, :start=>10, :end=>200
      sim.events = g.events
      sim.at(1) {sim.node(1).sendDataTo 'a'*2048, 'dtn://kasuari2/'; false}
    end

    should 'deliver the bundle' do
      assert_equal 1, traffic_model.deliveryRatio
    end

    should 'deliver the bundle during the second contact' do
      assert_equal 11, traffic_model.totalDelay.to_i
    end

  end

end

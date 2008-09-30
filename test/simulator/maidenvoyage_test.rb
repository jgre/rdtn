$:.unshift File.join(File.dirname(__FILE__), '../../sim/maidenvoyage')

require 'maidenvoyage'
require 'graph'

class TestMaidenVoyage < Test::Unit::TestCase

  should 'run Shoulda tests' do
    @val = 42
    assert true
  end

  simulation_context 'MaidenVoyage simulation_context' do

    prepare do
      g = Sim::Graph.new
      g.edge 1 => 2, :start => 10, :end => 60
      sim.events = g.events
      sim.at(1) {sim.node(1).sendDataTo 'test', 'dtn://kasuari2/'; false}
    end

    should 'give access to a simulator instance' do
      assert_instance_of Sim::Core, sim
    end

    should 'reuse a simulator instance once it was created' do
      sim1 = sim
      sim2 = sim
      assert_equal sim1.object_id, sim2.object_id
    end

    should 'run a simulation' do
      assert_equal 60, sim.time
    end

    should 'create a network model' do
      assert_instance_of TrafficModel, traffic_model
    end

    should 'provide appropriate start time values for the traffic model' do
      assert_equal 9, traffic_model.totalDelay.to_i
    end

    should 'deliver bundles' do
      assert_equal 1, traffic_model.numberOfBundles
      assert_equal 1, traffic_model.numberOfExpectedBundles
      assert_equal 1, traffic_model.deliveryRatio
    end

  end

  simulation_context 'Network fixtures' do

    # The network must be configured before the prepare-block, as the prepare
    # starts the simulation.
    network :simple

    should 'be loaded into the simulator' do
      assert_equal 6, network_model.numberOfNodes
      assert_equal 6, network_model.numberOfContacts
    end

  end

  simulation_context 'Workload fixtures' do

    network :simple
    workload :single_shot

    should 'be loaded into the simulator' do
      assert_equal 1, traffic_model.numberOfBundles
    end

  end

end

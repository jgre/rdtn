$:.unshift File.join(File.dirname(__FILE__), '../../sim/maidenvoyage')

require 'maidenvoyage'
require 'graph'

class TestMaidenVoyage < Test::Unit::TestCase

  should 'run Shoulda tests' do
    assert true
  end

  context 'MaidenVoyage context' do

    prepare do
      @prepval = 42

      g = Sim::Graph.new
      g.edge 1 => 2, :start => 1, :end => 60
      sim.events = g.events
      sim.createNodes(2)
    end

    should 'execute prepare blocks for setup' do
      assert_equal 42, @prepval
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
      assert_instance_of NetworkModel, network_model
      assert_equal 60, network_model.duration
    end

  end

  context 'Network fixtures' do

    # The network must be configured before the prepare-block, as the prepare
    # starts the simulation.
    network :simple

    # There must be a prepare block -- even when it's empty -- as it is used to
    # start the simulator
    prepare {}

    should 'be loaded into the simulator' do
      assert_equal 6, network_model.numberOfNodes
      assert_equal 6, network_model.numberOfContacts
    end

  end

  context 'Workload fixtures' do

    network :simple
    workload :single_shot

    prepare {}

    should 'be loaded into the simulator' do
    end

  end

end

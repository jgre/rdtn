$:.unshift File.join(File.dirname(__FILE__), '../../sim/maidenvoyage')

require 'maidenvoyage'
require 'graph'
require 'epidemicrouter'

class TestErrorLogging < Test::Unit::TestCase

  simulation_context 'Simulating a contact that is too short' do

    prepare do
      g = Sim::Graph.new
      g.edge 1 => 2, :start => 1, :end => 3
      sim.events = g.events

      sim.nodes.router :epidemic

      sim.at(1) {sim.node(1).sendDataTo 'a'*3073, 'dtn://kasuari2/'; false}
    end

    should 'not deliver a bundle' do
      assert_equal 0, traffic_model.deliveryRatio
    end

    should 'count half of the bundle as failed transmission' do
      assert_equal 2048, traffic_model.failedTransmissions
    end

  end

end

$: << File.join(File.dirname(__FILE__), '..', 'lib')
$:.unshift File.join(File.dirname(__FILE__), '../sim/maidenvoyage')

require 'test/unit'
require 'rubygems'
require 'shoulda'
require 'spraywaitrouter'
require 'daemon'
require 'maidenvoyage'
require 'graph'

class TestSprayWaitRouter < Test::Unit::TestCase

  simulation_context 'SprayWait' do

    prepare do
      g = Sim::Graph.new
      g.edge 1 => 2, :start => 1, :end => 4
      g.edge 1 => 3, :start => 2, :end => 5
      g.edge 1 => 4, :start => 3, :end => 6
      g.edge 1 => 5, :start => 7, :end => 10
      g.edge 2 => 6, :start => 0, :end => 4
      g.edge 2 => 7, :start => 2, :end => 5
      g.edge 3 => 8, :start => 2, :end => 5
      g.edge 6 => 9, :start => 3, :end => 5
      sim.events = g.events

      sim.nodes.router :spraywait, :initial_copycount => 4

      sim.at(0) {sim.node(1).sendDataTo "bla", "dtn://kasuari5/"; false}
    end

    should 'pass half of the available copies to each contact' do
      assert_equal 4, traffic_model.numberOfTransmissions
      bundle = traffic_model.regularBundles.first
      assert !bundle.incidents[2].empty?
      assert !bundle.incidents[3].empty?
      assert !bundle.incidents[5].empty?
      assert !bundle.incidents[6].empty?
      
      assert bundle.incidents[4].empty?
      assert bundle.incidents[7].empty?
      assert bundle.incidents[8].empty?
      assert bundle.incidents[9].empty?
    end

    should 'deliver the bundle to the destination' do
      assert_equal 1, traffic_model.deliveryRatio
    end

  end

  simulation_context 'SprayWait with repeated contatcs' do

    prepare do
      g = Sim::Graph.new
      g.edge 1 => 2, :start => 1,  :end => 3
      g.edge 1 => 2, :start => 5,  :end => 8
      g.edge 1 => 5, :start => 10, :end => 12
      g.edge 2 => 3, :start => 10, :end => 12
      g.edge 2 => 4, :start => 13, :end => 15
      sim.events = g.events

      sim.nodes.router :spraywait, :initial_copycount => 4

      sim.at(0) {sim.node(1).sendDataTo "bla", "dtn://kasuari4/"; false}
    end

    should 'deliver the bundle' do
      assert_equal 1, traffic_model.deliveryRatio
    end

    should 'not waste copies on repeated contacts' do
      bundle = traffic_model.regularBundles.first
      assert !bundle.incidents[2].empty?
      assert !bundle.incidents[3].empty?
      assert !bundle.incidents[5].empty?
    end

    should 'not transmit more bundles than the limit' do
      assert_operator 4, :>=, traffic_model.numberOfTransmissions
    end

  end

  simulation_context 'SprayWait with loops' do

    prepare do
      g = Sim::Graph.new
      g.edge 1 => 2, :start => 1, :end => 3
      g.edge 2 => 3, :start => 2, :end => 4
      g.edge 1 => 3, :start => 5, :end => 7
      g.edge 3 => 4, :start => 8, :end => 10
      sim.events = g.events
    end

  end
  
end

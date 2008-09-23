$:.unshift File.join(File.dirname(__FILE__), '../../sim/maidenvoyage')

require 'maidenvoyage'
require 'graph'
require 'epidemicrouter'

class TestFlooding < Test::Unit::TestCase

  simulation_context 'On the discworld scenario, epidemic routing' do

    network :discworld
    workload :single_sender_multicast

    prepare do
      sim.router(:epidemic)
    end

    should 'transmit 30 bundles' do
      assert_equal 30, traffic_model.numberOfBundles
    end

    should 'deliver all bundles' do
      assert_equal 150, traffic_model.numberOfExpectedBundles
      assert_equal 1, traffic_model.deliveryRatio
    end

    should 'replicate each bundle to each node'

  end

end

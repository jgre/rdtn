$:.unshift File.join(File.dirname(__FILE__), '../../sim/maidenvoyage')

require 'maidenvoyage'
require 'graph'
require 'epidemicrouter'

class TestFlooding < Test::Unit::TestCase

  simulation_context 'On the discworld scenario, epidemic routing' do

    network :discworld
    workload :single_sender_multicast

    prepare do
      sim.nodes.router(:epidemic)
    end

    should 'transmit 30 bundles' do
      assert_equal 30, traffic_model.numberOfBundles
    end

    should 'deliver all bundles' do
      assert_equal 150, traffic_model.numberOfExpectedBundles
      assert_equal 1, traffic_model.deliveryRatio
    end

    should 'replicate each bundle to each node' do
      assert_equal 360, traffic_model.numberOfReplicas
    end

  end

  simulation_context 'Epidemic routing with vaccinations' do

    network :moving_intermediary

    prepare do
      sim.nodes.router(:epidemic, :vaccination => true)

      sim.at(1){self.bndl=sim.node(1).sendDataTo 'test','dtn://kasuari4/'; puts "Bundle #{self.bndl.bundleId}";false}
      sim.node(4).register {}
    end

    should 'deliver the bundle' do
      assert_equal 1, traffic_model.deliveryRatio
    end

    should 'transmit 1 content bundles and 1 vaccination' do
      assert_equal 1, traffic_model.numberOfBundles
      assert_equal 1, traffic_model.numberOfSignalingBundles
    end

    should 'not replicate the bundle to all nodes' do
      assert_operator traffic_model.numberOfReplicas(self.bndl), :<,
        network_model.numberOfNodes - 1
    end

  end

end

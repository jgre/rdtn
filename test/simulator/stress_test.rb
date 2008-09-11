$:.unshift File.join(File.dirname(__FILE__), '../../sim/maidenvoyage')

require 'maidenvoyage'
require 'graph'

class TestStress < Test::Unit::TestCase

  context 'Under stress the simulator' do

    network  :two_connected_nodes
    workload :sending_many_bundles

    prepare {}

    should 'deliver all bundles' do
      assert_equal 1200, traffic_model.numberOfBundles
      assert_equal 1, traffic_model.deliveryRatio
    end

  end

end

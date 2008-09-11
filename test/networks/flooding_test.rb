$:.unshift File.join(File.dirname(__FILE__), '../../sim/maidenvoyage')

require 'rubygems'
require 'test/unit'
require 'shoulda'
require 'maidenvoyage'

class FloodingTest < MaidenVoyage::TestCase

  context 'A network with flood routing' do

    network  :simple
    workload :single_sender_broadcast

    setup do
      sim.nodes.each_value {|node| node.router(:flooding)}
      @bundle = Bundling::Bundle.new('test', 'dtn:all')
    end

    should 'deliver at least 50% of all bundles' do
      assert_operator traffic.delivery_ratio, :>=, 0.5
    end

  end

end

$: << File.join(File.dirname(__FILE__), '..', 'lib')
$:.unshift File.join(File.dirname(__FILE__), '../sim/maidenvoyage')

require 'test/unit'
require 'rubygems'
require 'shoulda'
require 'hopcountblock'
require 'maidenvoyage'

class TestHopCountBlock < Test::Unit::TestCase

  should 'serialize and parse itself' do
    bundle = Bundling::Bundle.new('test', 'dtn://test.dtn/')
    block  = HopCountBlock.new(bundle)

    sio = StringIO.new(block.to_s)
    assert_equal HopCountBlock::HOPCOUNT_BLOCK, sio.getbyte
    
    block2 = HopCountBlock.new(bundle)
    block.parse(sio)

    assert_equal block.hopCount, block2.hopCount
  end

  should 'serialize and parse inside a bundle' do
    bundle = Bundling::Bundle.new('test', 'dtn://test.dtn/')
    block  = HopCountBlock.new(bundle)
    bundle.addBlock(block)

    sio = StringIO.new(bundle.to_s)
    bundle2 = Bundling::Bundle.new
    bundle2.parse(sio)

    assert_equal 'test', bundle2.payload
    block2 = bundle2.findBlock(HopCountBlock)
    assert_not_nil block2
    assert_equal block.hopCount, block2.hopCount
  end

  simulation_context 'Sending a bundle with hop count block' do

    prepare do
      g = Sim::Graph.new
      g.edge 1 => 2, :start => 10, :end => 15
      g.edge 2 => 3, :start => 10, :end => 15
      sim.events = g.events

      sim.nodes.router :epidemic

      dest = 'dtn://channel/'
      bundle = Bundling::Bundle.new('test', dest, nil, :multicast => true)
      block  = HopCountBlock.new(bundle)
      bundle.addBlock(block)
      sim.at(1) {sim.node(2).register(dest) {|b| @bundle2 = b}; false}
      sim.at(1) {sim.node(3).register(dest) {|b| @bundle3 = b}; false}
      sim.at(1) {sim.node(1).sendBundle bundle; false}
    end

    should 'increment the hop count' do
      assert_equal 1, traffic_model.deliveryRatio
      assert_not_nil @bundle2
      assert_not_nil @bundle3
      hc2 = @bundle2.findBlock(HopCountBlock)
      hc3 = @bundle3.findBlock(HopCountBlock)
      assert_not_nil hc2
      assert_not_nil hc3
      assert_equal 1, hc2.hopCount
      assert_equal 2, hc3.hopCount
    end

  end

end

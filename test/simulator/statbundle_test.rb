$:.unshift File.join(File.dirname(__FILE__), '../../sim/stats')
$:.unshift File.join(File.dirname(__FILE__), '../../lib')

require 'rubygems'
require 'test/unit'
require 'shoulda'
require 'statbundle'
require 'bundle'

class StatBundleTest < Test::Unit::TestCase

  def setup
    @dest   = 2
    @src    = 1
    @pl     = 'test'
    @t0     = Time.now - 10
    @bundle = Bundling::Bundle.new(@pl, "dtn://kasuari#@dest/tag", 
                                        "dtn://kasuari#@src")
    @sbndl  = StatBundle.new(@t0, @bundle)
  end

  should 'copy id from a RDTN bundle' do
    assert_equal @bundle.bundleId, @sbndl.bundleId
  end

  should 'extract the source and destination node id from a RDTN bundle' do
    assert_equal @dest, @sbndl.dest
    assert_equal @src,  @sbndl.src
  end

  should 'take the playload size from a RDTN bundle' do
    assert_equal @pl.length, @sbndl.payload_size
  end

  should 'keep the creation time relative to the start of the simulation' do
    assert_equal @bundle.created - @t0.to_i, @sbndl.created
  end

  context 'Delivered bundles' do

    setup do
      @sbndl.forwarded(15, 1, 2)
    end

    should 'be marked accordingly' do
      assert @sbndl.delivered?
    end

    should 'calculate the delay' do
      assert_equal 15-@sbndl.created.to_i, @sbndl.averageDelay
    end

  end

  context 'Bundles replicated to nodes that are not a destination' do

    setup do
      @sbndl.forwarded(20, 1, 3)
    end

    should 'NOT be marked as delivered' do
      assert !@sbndl.delivered?
    end

    should 'be counted as replica' do
      assert_equal 1, @sbndl.nReplicas
    end

  end

end

$: << File.join(File.dirname(__FILE__), '..', 'lib')

require 'test/unit'
require 'rubygems'
require 'shoulda'
require 'copycountblock'

class TestCopyCountBlock < Test::Unit::TestCase

  def setup
    @bundle = Bundling::Bundle.new('test', 'dtn://test.dtn/')
    @cc     = CopyCountBlock.new(@bundle, 5)
    @bundle.addBlock @cc
  end

  should 'serialize and parse itself' do
    sio = StringIO.new(@cc.to_s)
    byte = sio.respond_to?(:getbyte) ? sio.getbyte : sio.getc
    assert_equal CopyCountBlock::COPYCOUNT_BLOCK, byte

    cc2 = CopyCountBlock.new(@bundle)
    cc2.parse(sio)
    assert_equal @cc.copycount, cc2.copycount
  end

  should 'create a copy of itself and its bundle with decremented counts' do
    bundle2, cc2 = @cc.bisect!
    assert_not_equal @bundle.object_id, bundle2.object_id
    assert_equal @bundle.bundleId, bundle2.bundleId
    assert_equal 3, @cc.copycount
    assert_equal 2, cc2.copycount
    assert_equal 3, @bundle.findBlock(CopyCountBlock).copycount
    assert_equal 2, bundle2.findBlock(CopyCountBlock).copycount
  end

end

$: << File.join(File.dirname(__FILE__), '..', 'lib')

require 'test/unit'
require 'rubygems'
require 'shoulda'
require 'ccnblock'

class TestCCNBlock < Test::Unit::TestCase

  def setup
    @bundle = Bundling::Bundle.new('test', 'dtn://test.dtn/')
    @uri    = "http://example.com/feed/"
    @ccn    = CCNBlock.new(@bundle, @uri, :publish)
    @bundle.addBlock @ccn
  end

  should 'serialize and parse itself' do
    sio = StringIO.new(@ccn.to_s)
    byte = sio.respond_to?(:getbyte) ? sio.getbyte : sio.getc
    assert_equal CCNBlock::CCN_BLOCK, byte

    ccn2 = CCNBlock.new(@bundle)
    ccn2.parse(sio)
    assert_equal @ccn.uri, ccn2.uri
    assert_equal @ccn.method, ccn2.method
    assert_equal :publish, ccn2.method
  end

end

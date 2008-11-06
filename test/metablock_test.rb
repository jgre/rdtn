$: << File.join(File.dirname(__FILE__), '..', 'lib')

require 'test/unit'
require 'rubygems'
require 'shoulda'
require 'metablock'

class TestMetadataBlock < Test::Unit::TestCase

  def setup
    @bundle = Bundling::Bundle.new('test', 'dtn://test.dtn/')
    @meta   = MetadataBlock.new(@bundle, 'metadta', 100)
  end

  should 'serialize and parse itself' do
    sio = StringIO.new(@meta.to_s)
    byte = sio.respond_to?(:getbyte) ? sio.getbyte : sio.getc
    assert_equal MetadataBlock::METADATA_BLOCK, byte

    meta2 = MetadataBlock.new(@bundle)
    meta2.parse(sio)
    assert_equal @meta.metadata, meta2.metadata
    assert_equal @meta.ontology, meta2.ontology
  end

  should 'translate Symbols to ontology numbers' do
    meta = MetadataBlock.new(@bundle, 'metadata', :contentType)
    assert_equal 101, meta.ontology
  end

  should 'translate ontology number ot symbols' do
    meta = MetadataBlock.new(@bundle, 'metadata', 101)
    assert_equal :contentType, meta.ontologySymbol
  end

end

require "bundle"

class CCNBlock < Bundling::Block

  CCN_BLOCK = 98

  include GenParser

  field :ccnblockLength, :decode => GenParser::SdnvDecoder
  field :uri,            :decode => GenParser::NullTerminatedDecoder
  field :method,         :decode => GenParser::NullTerminatedDecoder
  field :revision,       :decode => GenParser::NullTerminatedDecoder

  def initialize(bundle, uri = nil, method = nil, options = {})
    super(bundle)
    @uri      = uri
    @method   = method
    @revision = options[:revision] || 0
  end

  def to_s
    data = ""
    data << CCN_BLOCK
    data << flags
    data << Sdnv.encode(@uri.length + @method.length)
    data << @uri
    data << "\0"
    data << @method.to_s
    data << "\0"
    data << @revision.to_s
    data << "\0"
    data
  end

  def method
    @method.to_sym
  end

end

regBundleBlock(CCNBlock::CCN_BLOCK, CCNBlock)

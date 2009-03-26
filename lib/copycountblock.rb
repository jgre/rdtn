require "bundle"

class CopyCountBlock < Bundling::Block

  COPYCOUNT_BLOCK = 97

  include GenParser

  field :ccblockLength, :decode => GenParser::SdnvDecoder
  field :copycount,     :decode => GenParser::SdnvDecoder

  def initialize(bundle, copycount = nil)
    super(bundle)
    @copycount = copycount
  end

  def to_s
    data = ""
    data << COPYCOUNT_BLOCK
    data << flags
    cc_str = Sdnv.encode(self.copycount)
    data << Sdnv.encode(cc_str.length)
    data << cc_str
    data
  end

  def bisect!
    ret_bundle = @bundle.deepCopy
    ret_cc     = ret_bundle.findBlock(CopyCountBlock)
    ret_cc.copycount = (@copycount / 2.0).truncate
    @copycount = (@copycount / 2.0).ceil
    [ret_bundle, ret_cc]
  end

end

regBundleBlock(CopyCountBlock::COPYCOUNT_BLOCK, CopyCountBlock)

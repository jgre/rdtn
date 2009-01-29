require 'bundle'
require 'bundleworkflow'

class HopCountBlock < Bundling::Block
  HOPCOUNT_BLOCK = 195

  include GenParser

  field :hcblock, :decode => GenParser::SdnvDecoder
  field :hopCount, :decode => GenParser::SdnvDecoder

  def initialize(bundle, hc = 0)
    super(bundle)
    @hopCount = hc
  end

  def to_s
    data = ""
    data << HOPCOUNT_BLOCK
    data << flags
    codedHC = Sdnv.encode(@hopCount)
    data << Sdnv.encode(codedHC.length)
    data << codedHC
    data
  end

end

regBundleBlock(HopCountBlock::HOPCOUNT_BLOCK, HopCountBlock)

class HopCounter < Bundling::TaskHandler

  def processBundle(bundle)
    if (hc = bundle.findBlock(HopCountBlock))
      hc.hopCount += 1 unless bundle.srcEid == @config.localEid
    end
    self.state = :processed
  end

end

regWFTask(5, HopCounter)

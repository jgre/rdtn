require "bundle"

class MetadataBlock < Bundling::Block
 
 METADATA_BLOCK = 2

 include GenParser

  attr_accessor :metadata
  attr_accessor :ontology

  @@storePolicy = :memory

  def initialize(bundle, metadata = nil, ontology = 100)
    super(bundle)
    self.metadata = metadata
    self.ontology = ontology

    defField(:mdblockLength, :decode => GenParser::SdnvDecoder,
	       :block => lambda {|len| defField(:metadata, :length => len)})
	       
    # if (self.containsEidReference?)
    #   defField()
    # end
    
    defField(:ontology, :decode => GenParser::SdnvDecoder,
             :handler => :ontology=)
    defField(:metadata, :handler => :metadata=)
  end

  def to_s
    data = ""
    data << METADATA_BLOCK
    data << flags
    data << Sdnv.encode(self.metadataLength)
    data << Sdnv.encode(self.ontology)
    data << self.metadata
    return data
  end

  def metadata
    case @@storePolicy
    when :memory
	@metadata
    when :random
	if @metadataLength: open("/dev/urandom") {|f| f.read(@metadataLength)}
	else "" end
    else
	nil
    end
  end

  def ontology
      @ontology
  end
  
  def ontology=(o)
      @ontology = o
  end
  
  def metadata=(md)
    case @@storePolicy
    when :memory
	@metadata = md
    when :random
	@metadataLength = md.length if md
	@metadata       = nil
    end
  end

  def metadataLength
    if @metadataLength: @metadataLength
    else @metadata.length end
  end

  def MetadataBlock.storePolicy=(policy)
    @@storePolicy = policy
  end
end

regBundleBlock(MetadataBlock::METADATA_BLOCK, MetadataBlock)

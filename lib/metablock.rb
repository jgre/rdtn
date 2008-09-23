require "bundle"

class MetadataBlock < Bundling::Block
 
  METADATA_BLOCK = 2
  Ontologies     = {
    :contentType => 101
  }

  include GenParser

  field :mdblockLength, :decode => GenParser::SdnvDecoder
  field :ontology,      :decode => GenParser::SdnvDecoder
  field :metadata,      :length => :mdblockLength

  def self.ontologyNumber(ontology)
    ontology.is_a?(Symbol) ? MetadataBlock::Ontologies[ontology] : ontology
  end

  def self.ontologySymbol(ontology)
    unless ontology.is_a?(Symbol)
      pair = MetadataBlock::Ontologies.find {|sym, num| ontology == num}
      pair[0] if pair
    else
      ontology
    end
  end

  def initialize(bundle, metadata = nil, ontology = 100)
    super(bundle)
    self.metadata = metadata
    self.ontology = MetadataBlock.ontologyNumber(ontology)
  end

  def ontologySymbol
    MetadataBlock.ontologySymbol(@ontology)
  end

  def to_s
    data = ""
    data << METADATA_BLOCK
    data << flags
    data << Sdnv.encode(self.metadata.length)
    data << Sdnv.encode(self.ontology)
    data << self.metadata
    return data
  end

end

regBundleBlock(MetadataBlock::METADATA_BLOCK, MetadataBlock)

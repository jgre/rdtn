#  Copyright (C) 2007 Janico Greifenberg <jgre@jgre.org> and 
#  Dirk Kutscher <dku@tzi.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

require "rdtnerror"
require "configuration"
require "sdnv"
require "queue"
require "eidscheme"
require "rdtnevent"
require "genparser"
require "time"
require "forwardlog"

module Bundling

  class NoFragment < ProtocolError
    def initialize
      super("Bundles that are not fragments cannot be reassembled")
    end
  end

  class FragmentGap < ProtocolError
    def initialize
      super("Cannot reassemble the fragments. There are missing bytes between them")
    end
  end

  class FragmentTargetSizeTooSmall < ProtocolError
    def initialize(targetSize, headerSize)
      super("Cannot fragment to target size #{targetSize} bytes, as the header requires #{headerSize} bytes.")
    end
  end

  class UnknownBlockType < ProtocolError
    def initialize(blockType)
      super("Unknown block type #{blockType}")
    end
  end

  class BlockTypeInUse < ProtocolError
    def initialize(blockType, klass)
      super("Block type #{blockType} already used for class #{klass.name}")
    end
  end

  class ParserManager

    # Hash of bundles that are currently being received by convergence layers
    # We index the bundles by the object_id of the queue that is filled by the
    # convergence layer.
    @@incomingBundles = {}

    def ParserManager.registerEvents(evDis)
      evDis.subscribe(:bundleData) do |*args|
	ParserManager::handleBundleData(evDis, *args)
      end

      #TODO start housekeeping thread
    end

    def ParserManager.handleBundleData(evDis, queue, link)
      if not @@incomingBundles.has_key?(queue.object_id)
	@@incomingBundles[queue.object_id] = ParserManager.new(evDis, link)
	rdebug(self, "Adding new entry to @incomingBundles #{queue.object_id}")
      end

      if queue.closed?
	rwarn(self, "':bundleData' event received, but the queue is closed.")
	@@incomingBundles.delete(queue.object_id)
	return
      end

      pm = @@incomingBundles[queue.object_id]
      pm.doParse(queue)
      @@incomingBundles.delete(queue.object_id) unless pm.active?

    end

    def initialize(evDis, link)
      @evDis = evDis
      @active = true
      @bundle = Bundle.new
      neighbor = link ? link.remoteEid : nil
      @bundle.forwardLog.addEntry(:incoming, :transmitted, neighbor, link)
      @idleSince = nil

      @evDis.subscribe(:linkClosed) do |lnk|
	if lnk == @link
	  # TODO Do reactive fragmentation and cleanup
	end
      end
    end

    def doParse(queue)
      begin
	@idleSince = nil
	@bundle.parse(queue)
      rescue InputTooShort => detail
	@idleSince = RdtnTime.now
	rinfo(self, "Input too short need to read #{detail.bytesMissing} (#{queue.length - queue.pos} given)")
      rescue ProtocolError => msg
	rerror(self, "Bundle parser error: #{msg}")
	queue.close
	@active = false
      rescue IOError => msg
	rerror(self, "Bundle parser IO error: #{msg}")
	@active = false
      else
	if @bundle.parserFinished?
	  rdebug(self, "Parsing Bundle finished")
	  @evDis.dispatch(:bundleParsed, @bundle)
	  queue.close
	  @active = false
	end
      end
    end

    def active?
      return @active
    end

  end


  class PrimaryBundleBlock

    include GenParser

    attr_accessor :version, :procFlags, :cosFlags, :srrFlags, :blockLength,
      :destSchemeOff, :destSspOff, :srcSchemeOff, :srcSspOff,
      :repToSchemeOff, :repToSspOff, :custSchemeOff, :custSspOff,
      :creationTimestamp, :creationTimestampSeq, :lifetime, :dictLength,
      :destEid, :srcEid, :reportToEid, :custodianEid,
      :fragmentOffset, :aduLength,
      :bytesToRead, :queue

    @@lastTimestamp = 0
    @@lastSeqNo = 0

    def initialize(bundle, destEid=nil, srcEid=nil, reportToEid=nil,
		   custodianEid=nil)
      @bundle = bundle
      @version = 5
      @procFlags = 0
      @cosFlags = 0
      @srrFlags = 0
      @creationTimestamp = (RdtnTime.now - Time.gm(2000)).to_i
      if @creationTimestamp == @@lastTimestamp
	@@lastSeqNo = @creationTimestampSeq = @@lastSeqNo + 1
      else
	@@lastSeqNo = @creationTimestampSeq = 0
      end
      @@lastTimestamp = @creationTimestamp
      @lifetime = 120
      @destEid = EID.new(destEid)
      @srcEid = EID.new(srcEid)
      if not reportToEid
	@reportToEid = EID.new(destEid)
      else
	@reportToEid = EID.new(reportToEid)
      end
      @custodianEid = EID.new(custodianEid)

      @bytesToRead = -1 # Unknown

      defField(:version, :length => 1, :decode => GenParser::NumDecoder,
	       :condition => lambda {|version| Bundle::SUPPORTED_VERSIONS.include?(version)},
	       :handler => :defineFields)
    end

    def expired?
      RdtnTime.now.to_i > (creationTimestamp.to_i + lifetime.to_i + Time.gm(2000).to_i) 
    end

    def defineFields(version)
      @version = version
      defField(:procFlags, :decode => GenParser::SdnvDecoder, 
	       :handler => :procFlags=)

      defField(:blockLength, :decode => GenParser::SdnvDecoder,
	       :handler => :blockLength=)
      defField(:destSchemeOff, :decode => GenParser::SdnvDecoder,
	       :handler => :destSchemeOff=)
      defField(:destSspOff, :decode => GenParser::SdnvDecoder,
	       :handler => :destSspOff=)
      defField(:srcSchemeOff, :decode => GenParser::SdnvDecoder,
	       :handler => :srcSchemeOff=)
      defField(:srcSspOff, :decode => GenParser::SdnvDecoder,
	       :handler => :srcSspOff=)
      defField(:repToSchemeOff,:decode => GenParser::SdnvDecoder,
	       :handler => :repToSchemeOff=)
      defField(:repToSspOff, :decode => GenParser::SdnvDecoder,
	       :handler => :repToSspOff=)
      defField(:custSchemeOff, :decode => GenParser::SdnvDecoder,
	       :handler => :custSchemeOff=)
      defField(:custSspOff, :decode => GenParser::SdnvDecoder,
	       :handler => :custSspOff=)
      defField(:creationTimestamp, 
	       :decode => GenParser::SdnvDecoder, 
	       :handler => :creationTimestamp=)
      defField(:creationTimestampSeq, 
	       :decode => GenParser::SdnvDecoder, 
	       :handler => :creationTimestampSeq=)
      defField(:lifetime, :decode => GenParser::SdnvDecoder,
	       :handler => :lifetime=)
      defField(:dictLength, :decode => GenParser::SdnvDecoder,
	       :handler => :dictLength=,
	       :block => lambda {|len| defField(:dict, :length => len)})
      defField(:dict, :handler => :dict=)
      # These fields are only enabled (ignore => false) when the
      # corresponding flags are set
      defField(:fragmentOff, :ignore => true, :handler => :fragmentOffset=,
	       :decode => GenParser::SdnvDecoder)
      defField(:totalADUlen, :ignore => true, :handler => :totalADULen=,
	       :decode => GenParser::SdnvDecoder)
    end

    def bundleId
      "#{@srcEid}-#{@creationTimestamp}-#{@creationTimestampSeq}-#{@fragmentOffset}".hash
    end

    def dict=(dict)
      sio = StringIO.new(dict)

      @destEid = EID.new
      @srcEid = EID.new
      @reportToEid = EID.new
      @custodianEid = EID.new

      sio.pos = @destSchemeOff
      @destEid.scheme = sio.gets(0.chr).strip
      sio.pos = @destSspOff
      @destEid.ssp = sio.gets(0.chr).strip

      sio.pos = @srcSchemeOff
      @srcEid.scheme = sio.gets(0.chr).strip
      sio.pos = @srcSspOff
      @srcEid.ssp = sio.gets(0.chr).strip

      sio.pos = @repToSchemeOff
      @reportToEid.scheme = sio.gets(0.chr).strip
      sio.pos = @repToSspOff
      @reportToEid.ssp = sio.gets(0.chr).strip

      sio.pos = @custSchemeOff
      @custodianEid.scheme = sio.gets(0.chr).strip
      sio.pos = @custSspOff
      @custodianEid.ssp = sio.gets(0.chr).strip

    end

    def fragment=(set)
      @procFlags = set ? @procFlags | 0x1 : @procFlags & ~0x1
    end

    def fragment?
      (@procFlags & 0x1) != 0
    end

    def administrative=(set)
      @procFlags = set ? @procFlags | 0x2 : @procFlags & ~0x2
    end

    def administrative?
      (@procFlags & 0x2) != 0
    end

    def dontFragment=(set)
      @procFlags = set ? @procFlags | 0x4 : @procFlags & ~0x4
    end

    def dontFragment?
      (@procFlags & 0x4) != 0
    end  

    def requestCustody=(set)
      @procFlags = set ? @procFlags | 0x8 : @procFlags & ~0x8
    end

    def requestCustody?
      (@procFlags & 0x8) != 0
    end  

    def destinationIsSingleton=(set)
      @procFlags = set ? @procFlags | 0x10 : @procFlags & ~0x10
    end

    def destinationIsSingleton?
      (@procFlags & 0x10) != 0
    end  

    def requestApplicationAcknowledgement=(set)
      @procFlags = set ? @procFlags | 0x20 : @procFlags & ~0x20
    end

    def requestApplicationAcknowledgement?
      (@procFlags & 0x20) != 0
    end  


    # 00 :bulk, 
    # 01 :normal, 
    # 10 :expedited
    # 11 :undefined - for future use
    def priority
      return :expedited if (@procFlags & 0x100) != 0
      return :normal    if (@procFlags & 0x80) != 0
      return :bulk      if (@procFlags & 0x180) == 0  
      return :undefined 
    end

    def priority=(priority)
      @procFlags = @procFlags & 0xffe7f # this sets :bulk
      @procFlags = case priority
		   when :expedited then @procFlags | 0x100
		   when :normal    then @procFlags | 0x80
		   else                 @procFlags
		   end
    end   

    def receptionSrr=(set)
      @procFlags = set ? @procFlags | 0x4000 : @procFlags ^ 0x4000
    end

    def receptionSrr?
      (@procFlags & 0x4000) != 0
    end

    def custodyAcceptanceSrr=(set)
      @procFlags = set ? @procFlags | 0x8000 : @procFlags ^ 0x8000
    end

    def custodyAcceptanceSrr?
      (@procFlags & 0x8000) != 0
    end

    def forwardingSrr=(set)
      @procFlags = set ? @procFlags | 0x10000 : @procFlags ^ 0x10000
    end

    def forwardingSrr?
      (@procFlags & 0x10000) != 0
    end

    def deliverySrr=(set)
      @procFlags = set ? @procFlags | 0x20000 : @procFlags ^ 0x20000
    end

    def deliverySrr?
      (@procFlags & 0x20000) != 0
    end

    def deletionSrr=(set)
      @procFlags = set ? @procFlags | 0x40000 : @procFlags ^ 0x40000
    end

    def deletionSrr?
      (@procFlags & 0x40000) != 0
    end

    def lastBlock?
      # The primary bundle block cannot be the last block
      return false
    end

    def to_s
      data = ""
      data << @version
      pbb = ""
      dict = buildDict()
      data << Sdnv.encode(@procFlags)
      pbb << Sdnv.encode(@destSchemeOff)
      pbb << Sdnv.encode(@destSspOff)
      pbb << Sdnv.encode(@srcSchemeOff)
      pbb << Sdnv.encode(@srcSspOff)
      pbb << Sdnv.encode(@repToSchemeOff)
      pbb << Sdnv.encode(@repToSspOff)
      pbb << Sdnv.encode(@custSchemeOff)
      pbb << Sdnv.encode(@custSspOff)
      pbb << Sdnv.encode(@creationTimestamp)
      pbb << Sdnv.encode(@creationTimestampSeq)
      pbb << Sdnv.encode(@lifetime)
      pbb << Sdnv.encode(dict.length)
      pbb << dict

      @blockLength = pbb.length
      data << Sdnv.encode(@blockLength)
      data << pbb

      return data
    end

    private
    def buildDict
      eids = [[:destEid, :destSchemeOff=, :destSspOff=],
	[:srcEid, :srcSchemeOff=, :srcSspOff=],
	[:reportToEid, :repToSchemeOff=, :repToSspOff=],
	[:custodianEid, :custSchemeOff=, :custSspOff=]]
      offset = 0
      rbDict = {}
      strDict = ""
      eids.each do |eid, schemeOff, sspOff|
	scheme = EID.new(self.send(eid).to_s).scheme
	ssp = EID.new(self.send(eid).to_s).ssp
	if not rbDict.include?(scheme)
	  strDict << scheme + "\0"
	  rbDict[scheme] = offset
	  offset = strDict.length
	end
	res = self.send(schemeOff, rbDict[scheme])
	if not rbDict.include?(ssp)
	  strDict << ssp + "\0"
	  rbDict[ssp] = offset
	  offset = strDict.length
	end
	self.send(sspOff, rbDict[ssp])
      end
      return strDict
    end

  end

  # Representation of a Bundle including the parser and serialization. Refer to
  # the bundles protocol specification for the semantics of the attributes.

  class Bundle

    PAYLOAD_BLOCK = 1

    attr_accessor :incomingLink
    attr_reader   :forwardLog

    SUPPORTED_VERSIONS = [5]

    def initialize(payload=nil, destEid=nil, srcEid=nil, reportToEid=nil,
		   custodianEid=nil)
      @blocks = [PrimaryBundleBlock.new(self, destEid, srcEid, 
					reportToEid, custodianEid)]
      @custodyAccepted = false
      @deleted         = false
      @forwardLog = Bundling::ForwardLog.new
      if payload
	@blocks.push(PayloadBlock.new(self, payload))
	@blocks[-1].lastBlock = true
      end

      @custodyTimer = nil
      
    end

    # Most method calls are redirected to the PrimaryBundleBlock
    def method_missing(methodId, *args)
      @blocks[0].send(methodId, *args)
    end
    
    def deleted?
      @deleted
    end

    def delete
      @deleted = true
      # TODO: delete paylaod
    end

    def payload
      block = findBlock(PayloadBlock)
      if block
	block.payload
      else
	nil
      end
    end

    def payload=(pl)
      block = findBlock(PayloadBlock)
      if block
	block.payload = pl
      else
	addBlock(PayloadBlock.new(self, pl))
      end
    end

    def payloadLength
      block = findBlock(PayloadBlock)
      if block
	block.payloadLength
      else
	nil
      end
    end

    def findBlock(klass = nil)
      if klass
	@blocks.find {|block| block.class == klass}
      else
	@blocks.find {|block| yield block}
      end
    end

    def addBlock(block)
      if @blocks[-1] and @blocks[-1].class != PrimaryBundleBlock
	@blocks[-1].lastBlock = false 
      end
      block.lastBlock = true
      @blocks.push(block)
    end

    def to_s
      data = ""
      @blocks.each {|block| data << block.to_s}
      return data
    end

    def custodyAccepted?
      @custodyAccepted
    end

    def custodyAccepted=(acc)
      @custodyAccepted = acc
    end

    def dispatchPending?
      #TODO
      false
    end

    def forwardPending?
      #TODO
      false
    end

    def reassemblyPending?
      #TODO
      false
    end

    def retentionConstraints?
      custodyAccepted? or dispatchPending? or forwardPending? or reassemblyPending?
    end

    def removeRetentionConstraints
      @custodyAccepted = false
      # TODO: cancel pending transmissions in forwardLog
    end

    def parse(io)
      while not io.eof?
	if @blocks[-1].parserFinished?
	  blockType = io.getc
	  block = BundleBlockReg.instance.makeBlock(blockType, self)
	  addBlock(block)
	end
	oldPos = io.pos
	begin
	  @blocks[-1].parse(io)
	  #puts "Parsing Block #{@blocks[-1].class}, #{@blocks[-1].flags} #{io.pos}, #{io.length}" unless @blocks.length == 1
	rescue InputTooShort => detail
	  io.pos = oldPos
	  raise
	end
      end
    end

    def parserFinished?
      if @blocks.empty?
	return false
      else
	return (@blocks[-1].parserFinished? and @blocks[-1].lastBlock?)
      end
    end

    def fragmentNParts(n = 2)
      fragmentMaxSize(((self.bundleSize + n*self.headerSize).to_f/n.to_f).ceil)
    end

    def fragmentMaxSize(maxBytes)
      fragments = []
      if self.bundleSize > maxBytes
	frg1, frg2 = doFragment(maxBytes)
	return [frg1].concat(frg2.fragmentMaxSize(maxBytes))
      else
	return [self]
      end
    end

    def bundleSize
      return to_s.length
    end

    def Bundle.reassemble(fragment1, fragment2)
      if not fragment1.fragment? or not fragment2.fragment?
	raise NoFragment
      end
      if fragment1.fragmentOffset > fragment2.fragmentOffset
	fragment1, fragment2 = fragment2, fragment1
      end
      if fragment1.fragmentOffset + fragment1.payload.length < fragment2.fragmentOffset
	raise FragmentGap
      end

      #FIXME see if we need to take some blocks from the second fragment as well
      res = fragment1.deepCopy

      res.payload = fragment1.payload[0,fragment2.fragmentOffset] + fragment2.payload
      if res.payload.length == res.aduLength
	res.fragment = false
	res.aduLength = res.fragmentOffset = nil
      end
      return res
    end

    def Bundle.reassembleArray(fragments)
      case fragments.length
      when 0 then return nil
      when 1 then return fragments[0]
      else
	fragments.sort {|f1, f2| f1.fragmentOffset <=> f2.fragmentOffset}
	f1, *rest = fragments
	return Bundle.reassemble(f1, Bundle.reassembleArray(rest))
      end
    end
    
    def marshal_dump      
      [@blocks, @forwardLog, @custodyAccepted]
    end

    def marshal_load(arr)
      @blocks, @forwardLog, @custodyAccepted = arr
    end

    def to_yaml_properties
      %w{ @blocks @forwardLog @custodyAccepted }
    end

    def deepCopy
      ret = Bundle.new
      ret.forwardLog = @forwardLog.deepCopy
      ret.custodyAccepted = @custodyAccepted
      ret.blocks = @blocks.map {|block| block.clone}
      return ret
    end

    def setCustodyTimer(timer)
      @custodyTimer = timer
    end
    
    def removeCustodyTimer
      if (@custodyTimer) then
        @custodyTimer.stop
        @custodyTimer = nil
      end
    end

    attr_accessor :blocks
    attr_writer   :forwardLog
    protected :blocks, :blocks=, :forwardLog=

      private

    # Calculate the size of the "headers" (the primary block, extension
    # blocks, and the headers of the payload block). This is (roughly) the
    # stuff that needs to be repeated in all the fragments. As some
    # blocks only need to appear in one fragment and some SDNVs may become
    # smaller we err a bit on the high side here.

    def headerSize
      self.bundleSize - self.payload.length
    end

    # Returns two bundles. The first is no greater that targetSize bytes
    # containg first bytes of this
    # bundle, the second bundle contains the rest.

    def doFragment(targetSize)
      offset = targetSize-headerSize
      if offset <= 0
	raise FragmentTargetSizeTooSmall(targetSize, headerSize)
      end

      fragment1 = self.deepCopy
      fragment2 = self.deepCopy
      fragment1.payload = self.payload[0,offset]
      fragment2.payload = self.payload[offset..-1]
      fragment1.fragment = fragment2.fragment = true
      if not self.fragment?
	fragment1.fragmentOffset = 0
	fragment2.fragmentOffset = offset
	fragment1.aduLength = fragment2.aduLength = self.payload.length
      else
	# If we are fragmenting a bundle that is already a fragment the total
	# ADU is unchanged and the offset of the first fragment is the same as
	# the old offset. Only the offset of the second fragment is changed.
	fragment2.fragmentOffset = offset + self.fragmentOffset
      end

      return fragment1, fragment2

    end

  end

  class Block

    include GenParser

    attr_accessor :flags
    attr_reader :bundle
    protected :bundle

    def initialize(bundle)
      @flags   = 0
      @bundle  = bundle

      defField(:procFlags, :decode => GenParser::SdnvDecoder,
	       :handler => :flags=)
    end

    def replicateBlockForEveryFragment=(set)
      @flags = set ? @flags | 0x1 : @flags & ~0x1
    end

    def replicateBlockForEveryFragment?
      @flags & 0x1 != 0 
    end

    def transmitStatusIfBlockNotProcessed=(set)
      @flags = set ? @flags | 0x2 : @flags & ~0x2
    end

    def transmitStatusIfBlockNotProcessed?
      @flags & 0x2 != 0 
    end

    def deleteBundleIfBlockNotProcessed=(set)
      @flags = set ? @flags | 0x4 : @flags & ~0x4
    end

    def deleteBundleIfBlockNotProcessed?
      @flags & 0x4 != 0 
    end

    def lastBlock=(set)
      @flags = set ? @flags | 0x8 : @flags & ~0x8
    end

    def lastBlock?
      (@flags & 0x8) != 0 
    end

    def discardBlockIfNotProcessed=(set)
      @flags = set ? @flags | 0x10 : @flags & ~0x10
    end

    def discardBlockIfNotProcessed?
      @flags & 0x10 != 0 
    end

    def forwardedBlockWithoutProcessing=(set)
      @flags = set ? @flags | 0x20 : @flags & ~0x20
    end

    def forwardedBlockWithoutProcessing?
      @flags & 0x20 != 0 
    end

    def containsEidReference=(set)
      @flags = set ? @flags | 0x40 : @flags & ~0x40
    end

    def containsEidReference?
      (@flags & 0x40) != 0 
    end

  end

  class PayloadBlock < Block

    include GenParser

    attr_accessor :payload

    @@storePolicy = :memory

    def initialize(bundle, payload = nil)
      super(bundle)
      self.payload = payload
      self.flags   = 8 # last block

      defField(:plblockLength, :decode => GenParser::SdnvDecoder,
	       :block => lambda {|len| defField(:payload, :length => len)})
      defField(:payload, :handler => :payload=)
    end

    def to_s
      data = ""
      data << Bundle::PAYLOAD_BLOCK
      data << flags
      data << Sdnv.encode(self.payloadLength)
      data << self.payload
      return data
    end

    def payload
      case @@storePolicy
      when :memory
	@payload
      when :random
	if @payloadLength then open("/dev/urandom") {|f| f.read(@payloadLength)}
	else "" end
      else
	nil
      end
    end

    def payload=(pl)
      case @@storePolicy
      when :memory
	@payload = pl
      when :random
	@payloadLength = pl.length if pl
	@payload       = nil
      end
    end

    def payloadLength
      if @payloadLength then @payloadLength
      else @payload.length end
    end

    def PayloadBlock.storePolicy=(policy)
      @@storePolicy = policy
    end

  end

end # module Bundling

class BundleBlockReg

  include Singleton

  attr_accessor :blocks

  def initialize
    @blocks = {}
  end

  def regBlock(blockType, klass)
    if @blocks[blockType]
      raise Bundling::BlockTypeInUse.new(blockType, @blocks[blockType])
    end
    @blocks[blockType] = klass
  end

  def makeBlock(blockType, bundle)
    return @blocks[blockType].new(bundle) if @blocks[blockType]
    raise Bundling::UnknownBlockType.new(blockType)
  end

end

def regBundleBlock(blockType, klass)
  BundleBlockReg.instance.regBlock(blockType, klass)
end

regBundleBlock(Bundling::Bundle::PAYLOAD_BLOCK, Bundling::PayloadBlock)

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

  class ParserManager

    # Hash of bundles that are currently being received by convergence layers
    # We index the bundles by the object_id of the queue that is filled by the
    # convergence layer.
    @@incomingBundles = {}
    @@log = RdtnConfig::Settings.instance.getLogger(self.class.name)

    def ParserManager.registerEvents
      EventDispatcher.instance.subscribe(:bundleData) do |*args|
	ParserManager::handleBundleData(*args)
      end

      #TODO start housekeeping thread
    end

    def ParserManager.handleBundleData(queue, link)

	if not @@incomingBundles.has_key?(queue.object_id)
	  @@incomingBundles[queue.object_id] = ParserManager.new(link)
	  @@log.debug("Adding new entry to @incomingBundles #{queue.object_id}")
	end

	if queue.closed?
	  @@log.warn("':bundleData' event received, but the queue is closed.")
	  @@incomingBundles.delete(queue.object_id)
	  return
	end

	pm = @@incomingBundles[queue.object_id]
	pm.doParse(queue)
	@@incomingBundles.delete(queue.object_id) unless pm.active?

    end

    def initialize(link)
      @active = true
      @bundle = Bundle.new
      @bundle.incomingLink = link
      @idleSince = nil

      EventDispatcher.instance.subscribe(:linkClosed) do |lnk|
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
	@idleSince = Time.now
	@@log.info("Input too short need to read #{detail.bytesMissing} (#{queue.length - queue.pos} given)")
      rescue ProtocolError => msg
	@@log.error("Bundle parser error: #{msg}")
	queue.close
	@active = false
      rescue IOError => msg
	@@log.error("Bundle parser IO error: #{msg}")
	@active = false
      else
	if @bundle.parserFinished?
	  @@log.debug("Parsing Bundle finished")
	  EventDispatcher.instance.dispatch(:bundleParsed, @bundle)
	  queue.close
	  @active = false
	end
      end
    end

    def active?
      return @active
    end

  end

  # Representation of a Bundle including the parser and serialization. Refer to
  # the bundles protocol specification for the semantics of the attributes.
  
  class Bundle

    PAYLOAD_BLOCK = 1

    attr_accessor :incomingLink

    SUPPORTED_VERSIONS = [4, 5]

    def initialize(payload=nil, destEid=nil, srcEid=nil, reportToEid=nil,
		  custodianEid=nil)
      @log = RdtnConfig::Settings.instance.getLogger(self.class.name)
      @blocks = []
      if payload or destEid or srcEid
	@blocks.push(PrimaryBundleBlock.new(self, destEid, srcEid, 
					  reportToEid, custodianEid))
	@blocks.push(PayloadBlock.new(self, payload))
      end
    end

    # Most method calls are redirected to the blocks that make up the bundle.
    def method_missing(methodId, *args)
      return nil if @blocks.empty?
      @blocks.each do |block|
	begin
	  ret = block.send(methodId, *args)
	  return ret
	rescue NoMethodError => err
	end
      end
      
      return nil if methodId == :payload
      raise NoMethodError, methodId, caller
    end

    def to_s
      data = ""
      @blocks.each {|block| data << block.to_s}
      return data
    end

    def parse(io)
      while not io.eof?
	if @blocks.empty?
	  @blocks.push(PrimaryBundleBlock.new(self))
	elsif @blocks[-1].parserFinished?
	  blockType = io.getc
	  block = case blockType
		  when PAYLOAD_BLOCK: PayloadBlock.new(self)
		  else raise UnknownBlockType, blockType
		  end
	  @blocks.push(block)
	end
	oldPos = io.pos
	begin
	  @blocks[-1].parse(io)
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
      res = fragment1.clone

      res.payload = fragment1.payload[0,fragment2.fragmentOffset] + fragment2.payload
      if res.payload.length == res.aduLength
	res.fragment = false
	res.aduLength = res.fragmentOffset = nil
      end
      return res
    end

    def Bundle.reassembleArray(fragments)
      case fragments.length
      when 0: return nil
      when 1: return fragments[0]
      else
	fragments.sort {|f1, f2| f1.fragmentOffset <=> f2.fragmentOffset}
	f1, *rest = fragments
	return Bundle.reassemble(f1, Bundle.reassembleArray(rest))
      end
    end

    def marshal_load(bundleStr)     
      io=RdtnStringIO.new(bundleStr)
      @blocks = []
      self.parse(io)
      return self
    end

    def marshal_dump
      return self.to_s
    end

    def deepCopy
      ret = clone
      ret.blocks = @blocks.map {|block| block.clone}
      return ret
    end

    protected

    def blocks=(blocks)
      @blocks = blocks
    end

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
      @log = RdtnConfig::Settings.instance.getLogger(self.class.name)
      @bundle = bundle
      @version = 5
      @procFlags = 0
      @cosFlags = 0
      @srrFlags = 0
      @creationTimestamp = (Time.now - Time.gm(2000)).to_i
      if @creationTimestamp == @@lastTimestamp
	@@lastSeqNo = @creationTimestampSeq = @@lastSeqNo + 1
      else
	@@lastSeqNo = @creationTimestampSeq = 0
      end
      @@lastTimestamp = @creationTimestamp
      @lifetime = 60
      @destEid = EID.new(destEid)
      if not srcEid
	@srcEid = EID.new(RdtnConfig::Settings.instance.localEid)
      else
	@srcEid = EID.new(srcEid)
      end
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

    def defineFields(version)
      @version = version
      if version == 4
	defField(:procFlags, :length => 1, :decode => GenParser::NumDecoder,
		 :handler => :procFlags=)
	defField(:cosFlags, :length => 1, :decode => GenParser::NumDecoder,
		 :handler => :cosFlags=)
	defField(:srrFlags, :length => 1, :decode => GenParser::NumDecoder,
		 :handler => :srrFlags=)
      elsif version == 5
	defField(:procFlags, :decode => GenParser::SdnvDecoder, 
		 :handler => :procFlags=)
      end
      defField(:blockLength, :decode => GenParser::SdnvDecoder,
	       :handler => :blockLength=)
      if version == 4
	defField(:destSchemeOff, :length => 2, :decode => GenParser::NumDecoder,
		 :handler => :destSchemeOff=)
	defField(:destSspOff, :length => 2, :decode => GenParser::NumDecoder,
		 :handler => :destSspOff=)
	defField(:srcSchemeOff, :length => 2, :decode => GenParser::NumDecoder,
		 :handler => :srcSchemeOff=)
	defField(:srcSspOff, :length => 2, :decode => GenParser::NumDecoder,
		 :handler => :srcSspOff=)
	defField(:repToSchemeOff,:length => 2, :decode => GenParser::NumDecoder,
		 :handler => :repToSchemeOff=)
	defField(:repToSspOff, :length => 2, :decode => GenParser::NumDecoder,
		 :handler => :repToSspOff=)
	defField(:custSchemeOff, :length => 2, :decode => GenParser::NumDecoder,
		 :handler => :custSchemeOff=)
	defField(:custSspOff, :length => 2, :decode => GenParser::NumDecoder,
		 :handler => :custSspOff=)
	defField(:creationTimestamp, :length => 4, 
		 :decode => GenParser::NumDecoder, 
		 :handler => :creationTimestamp=)
	defField(:creationTimestampSeq, :length => 4, 
		 :decode => GenParser::NumDecoder, 
		 :handler => :creationTimestampSeq=)
	defField(:lifetime, :length => 4, :decode => GenParser::NumDecoder,
		 :handler => :lifetime=)
      elsif version == 5
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
      end
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
      if @version == 4  
        return :undefined if (@cosFlags & 0x3) != 0 
        return :expedited if (@cosFlags & 0x2) != 0  
        return :normal    if (@cosFlags & 0x1) != 0 
        return :bulk  
      elsif @version == 5  
        return :expedited if (@procFlags & 0x100) != 0
        return :normal    if (@procFlags & 0x80) != 0
        return :bulk      if (@procFlags & 0x180) == 0  
        return :undefined 
      end   
    end
    
    def priority=(priority)
      if @version == 4  
        @cosFlags & ~0x3 # this sets :bulk
        @cosFlags = case priority
		    when :expedited: @cosFlags | 0x2  
		    when :normal:    @cosFlags | 0x1
		    end
      elsif @version == 5
        @procFlags = @procFlags & 0xffe7f # this sets :bulk
	@procFlags = case priority
		     when :expedited: @procFlags | 0x100
		     when :normal: @procFlags | 0x80
		     else @procFlags
		     end
      end
    end   
    
    def receptionSrr=(set)
      if @version == 4
	@srrFlags = set ? @srrFlags | 0x1 : @srrFlags & ~0x1
      elsif @version == 5
	@procFlags = set ? @procFlags | 0x4000 : @procFlags ^ 0x4000
      end
    end
    
    def receptionSrr?
      if @version == 4
	(@srrFlags & 0x1) == 1
      elsif @version == 5
	(@procFlags & 0x4000) != 0
      end
    end
    
    def custodyAcceptanceSrr=(set)
      if @version == 4
	@srrFlags = set ? @srrFlags | 0x2 : @srrFlags & ~0x2
      elsif @version == 5
	@procFlags = set ? @procFlags | 0x8000 : @procFlags ^ 0x8000
      end
    end
    
    def custodyAcceptanceSrr?
      if @version == 4
	(@srrFlags & 0x2) == 1
      elsif @version == 5
	(@procFlags & 0x8000) != 0
      end
    end
    
    def forwardingSrr=(set)
      if @version == 4
	@srrFlags = set ? @srrFlags | 0x4 : @srrFlags & ~0x4
      elsif @version == 5
	@procFlags = set ? @procFlags | 0x10000 : @procFlags ^ 0x10000
      end
    end
    
    def forwardingSrr?
      if @version == 4
	(@srrFlags & 0x4) == 1
      elsif @version == 5
	(@procFlags & 0x10000) != 0
      end
    end
    
    def deliverySrr=(set)
      if @version == 4
	@srrFlags = set ? @srrFlags | 0x8 : @srrFlags & ~0x8
      elsif @version == 5
	@procFlags = set ? @procFlags | 0x20000 : @procFlags ^ 0x20000
      end
    end
    
    def deliverySrr?
      if @version == 4
	(@srrFlags & 0x8) == 1
      elsif @version == 5
	(@procFlags & 0x20000) != 0
      end
    end
    
    def deletionSrr=(set)
      if @version == 4
	@srrFlags = set ? @srrFlags | 0x10 : @srrFlags & ~0x10
      elsif @version == 5
	@procFlags = set ? @procFlags | 0x40000 : @procFlags ^ 0x40000
      end
    end
    
    def deletionSrr?
      if @version == 4
	(@srrFlags & 0x10) == 1
      elsif @version == 5
	(@procFlags & 0x40000) != 0
      end
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
      if @version == 4
	data << @procFlags
	data << @cosFlags
	data << @srrFlags
	pbb << [@destSchemeOff].pack('n')
	pbb << [@destSspOff].pack('n')
	pbb << [@srcSchemeOff].pack('n')
	pbb << [@srcSspOff].pack('n')
	pbb << [@repToSchemeOff].pack('n')
	pbb << [@repToSspOff].pack('n')
	pbb << [@custSchemeOff].pack('n')
	pbb << [@custSspOff].pack('n')
	pbb << [@creationTimestamp].pack('N')
	pbb << [@creationTimestampSeq].pack('N')
	pbb << [@lifetime].pack('N')
      elsif @version == 5
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
      end
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

  class Block

    include GenParser

    attr_accessor :flags
    attr_reader :bundle
    protected :bundle

    def initialize(bundle)
      @log = RdtnConfig::Settings.instance.getLogger(self.class.name)
      @flags   = 0
      @bundle  = bundle

      if @bundle.version == 4
	defField(:procFlags, :length => 1, :decode => GenParser::NumDecoder,
		 :handler => :flags=)
      elsif @bundle.version == 5
	defField(:procFlags, :decode => GenParser::SdnvDecoder,
		 :handler => :flags=)
      end
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
      @log = RdtnConfig::Settings.instance.getLogger(self.class.name)
      super(bundle)
      self.payload = payload
      self.flags   = 8 # last block

      defField(:plblockLength, :decode => GenParser::SdnvDecoder,
	       :object => @bundle,
	       :block => lambda {|len| defField(:payload, :length => len)})
      defField(:payload, :handler => :payload=, :object => @bundle)
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
	if @payloadLength: open("/dev/urandom") {|f| f.read(@payloadLength)}
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
      if @payloadLength: @payloadLength
      else @payload.length end
    end

    def PayloadBlock.storePolicy=(policy)
      @@storePolicy = policy
    end

  end

end # module Bundling

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
#
# $Id: fileup.py 8 2006-12-22 20:00:21Z jgre $

require "rdtnlog"
require "rdtnerror"
require "rdtnconfig"
require "sdnv"
require "queue"
require "eidscheme"
require "rdtnevent"
require "genparser"

module Bundling

  # The BundleLayer must be initialzed before bundles are received.

  class BundleLayer

    # Hash of bundles that are currently being received by convergence layers
    # We index the bundles by the object_id of the queue that is filled by the
    # convergence layer.
    @@incomingBundles = {}

    # Subscribe to all relevant events.

    def initialize

      EventDispatcher.instance.subscribe(:bundleData) do |queue, finished, cl|
	if not @@incomingBundles.has_key?(queue.object_id)
	  @@incomingBundles[queue.object_id] = Bundle.new
	  RdtnLogger.instance.debug("Adding new entry to @incomingBundles #{queue.object_id}")
	end

	if queue.closed?
	  RdtnLogger.instance.warn("':bundleData' event received, but the queue is closed.")
	  @@incomingBundles.delete(queue.object_id)
	  next
	end

	bundle = @@incomingBundles[queue.object_id]
	begin
	  bundle.parse(queue)
	rescue InputTooShort => detail
	  RdtnLogger.instance.info("Input too short need to read #{detail.bytesMissing} (#{queue.length} given)")
	  if finished
	    RdtnLogger.instance.error("Bundle parser error: The convergence layer thinks the bundle is ready, the parser, however, feels otherwise.")
	    queue.close
	    @@incomingBundles.delete(queue.object_id)
	  else
	    cl.bytesToRead = detail.bytesMissing 
	  end
	rescue ProtocolError => msg
	  RdtnLogger.instance.error("Bundle parser error: #{msg}")
	  queue.close
	  @@incomingBundles.delete(queue.object_id)
	rescue IOError => msg
	  RdtnLogger.instance.error("Bundle parser IO error: #{msg}")
	  @@incomingBundles.delete(queue.object_id)
	else
	  if finished
	    EventDispatcher.instance.dispatch(:bundleParsed, bundle)
	    queue.close
	    @@incomingBundles.delete(queue.object_id)
	  else
	    cl.bytesToRead = 1024
	  end
	end
      end
    end


  end

  SUPPORTED_VERSIONS = [4, 5]

  # Representation of a Bundle including the parser and serialization. Refer to
  # the bundles protocol specification for the semantics of the attributes.

  class Bundle
    attr_accessor :version, :procFlags, :cosFlags, :srrFlags, :blockLength,
      :destSchemeOff, :destSspOff, :srcSchemeOff, :srcSspOff,
      :repToSchemeOff, :repToSspOff, :custSchemeOff, :custSspOff,
      :creationTimestamp, :creationTimestampSeq, :lifetime, :dictLength,
      :destEid, :srcEid, :reportToEid, :custodianEid,
      :fragmentOffset, :aduLength,
      :payloadFlags, :payload,
      :bytesToRead, :queue

    attr_reader :state, :bundleId
    


    @@bundleCount=0

    def initialize(payload=nil, destEid=nil, srcEid=nil, reportToEid=nil,
		  custodianEid=nil)
      @bundleId=@@bundleCount+=1
      @payload = payload
      @version = 5
      @procFlags = 0
      @cosFlags = 0
      @srrFlags = 0
      @creationTimestamp = (Time.now - Time.gm(2000)).to_i
      @creationTimestampSeq = 0
      @lifetime = 3600
      @destEid = EID.new(destEid)
      if not srcEid
	@srcEid = EID.new(RDTNConfig.instance.localEid)
      else
	@srcEid = EID.new(srcEid)
      end
      if not reportToEid
	@reportToEid = EID.new(destEid)
      else
	@reportToEid = EID.new(reportToEid)
      end
      @custodianEid = EID.new(custodianEid)
      @payloadFlags = 8 # Last bundle

      @state = PrimaryBundleBlock.new(self)
      @bytesToRead = -1 # Unknown
    end

    def parse(io)
      @queue = io
      while not @queue.eof?
	@state = @state.readData(@queue)
      end
    end

    def fragment=(set)
      @procFlags = set ? @procFlags | 0x1 : @procFlags & ~0x1
    end
    
    def fragment?
      (@procFlags & 0x1) == 1
    end
    
    def administrative=(set)
      @procFlags = set ? @procFlags | 0x2 : @procFlags & ~0x2
    end
    
    def administrative?
      (@procFlags & 0x2) == 1
    end
    
    def dontFragment=(set)
      @procFlags = set ? @procFlags | 0x4 : @procFlags & ~0x4
    end
    
    def dontFragment?
      (@procFlags & 0x4) == 1
    end  
    
    def requestCustody=(set)
      @procFlags = set ? @procFlags | 0x8 : @procFlags & ~0x8
    end
    
    def requestCustody?
      (@procFlags & 0x8) == 1
    end  
    
    def destinationIsSingleton=(set)
      @procFlags = set ? @procFlags | 0x10 : @procFlags & ~0x10
    end
    
    def destinationIsSingleton?
      (@procFlags & 0x10) == 1
    end  
    
    def requestApplicationAcknowledgement=(set)
      @procFlags = set ? @procFlags | 0x20 : @procFlags & ~0x20
    end
    
    def requestApplicationAcknowledgement?
      (@procFlags & 0x20) == 1
    end  
    
    
    # 00 :bulk, 
    # 01 :normal, 
    # 10 :expedited
    # 11 :undefined - for future use
    def priority
      if version == 4  
        return :undefined if (@cosFlags & 0x3) == 1 
        return :expedited if (@cosFlags & 0x2) == 1  
        return :normal    if (@cosFlags & 0x1) == 1 
        return :bulk  
      end   
    end
    
    def priority=(priority)
      if version == 4  
        @cosFlags & ~0x3 # this sets :bulk
        case priority
        when :expedited: @cosFlags | 0x2  
        when :normal:    @cosFlags | 0x1
        end
      end
    end   
    
    
    def receptionSrr=(set)
      @srrFlags = set ? @srrFlags | 0x1 : @srrFlags & ~0x1
    end
    
    def receptionSrr?
      (@srrFlags & 0x1) == 1
    end
    
    def custodyAcceptanceSrr=(set)
      @srrFlags = set ? @srrFlags | 0x2 : @srrFlags & ~0x2
    end
    
    def custodyAcceptanceSrr?
      (@srrFlags & 0x2) == 1
    end
    
    def forwardingSrr=(set)
      @srrFlags = set ? @srrFlags | 0x4 : @srrFlags & ~0x4
    end
    
    def forwardingSrr?
      (@srrFlags & 0x4) == 1
    end
    
    def deliverySrr=(set)
      @srrFlags = set ? @srrFlags | 0x8 : @srrFlags & ~0x8
    end
    
    def deliverySrr?
      (@srrFlags & 0x8) == 1
    end
    
    def deletetionSrr=(set)
      @srrFlags = set ? @srrFlags | 0x10 : @srrFlags & ~0x10
    end
    
    def deletionSrr?
      (@srrFlags & 0x10) == 1
    end
    
    
    def replicateBlockForEveryFragment=(set, type = :payload)
      case type 
      when :payload: 
          @payloadFlags = set ? @payloadFlags | 0x1 : @payloadFlags & ~0x1
      end
    end
    
    def replicateBlockForEveryFragment?(type = :payload)
      case type 
      when :payload: 
          @payloadFlags & 0x1 == 1 
      end
    end
    
    def transmitStatusIfBlockNotProcessed=(set, type = :payload)
      case type 
      when :payload: 
          @payloadFlags = set ? @payloadFlags | 0x2 : @payloadFlags & ~0x2
      end
    end
    
    def transmitStatusIfBlockNotProcessed?(type = :payload)
      case type 
      when :payload: 
          @payloadFlags & 0x2 == 1 
      end
    end
    
    def discardBundleIfBlockNotProcessed=(set, type = :payload)
      case type 
      when :payload: 
          @payloadFlags = set ? @payloadFlags | 0x4 : @payloadFlags & ~0x4
      end
    end
    
    def discardBundleIfBlockNotProcessed?(type = :payload)
      case type 
      when :payload: 
          @payloadFlags & 0x4 == 1 
      end
    end
    
    def lastBlock=(set, type = :payload)
      case type 
      when :payload: 
          @payloadFlags = set ? @payloadFlags | 0x8 : @payloadFlags & ~0x8
      end
    end
    
    def lastBlock?(type = :payload)
      case type 
      when :payload: 
          @payloadFlags & 0x8 == 1 
      end
    end
    
    def discardBlockIfNotProcessed=(set, type = :payload)
      case type 
      when :payload: 
          @payloadFlags = set ? @payloadFlags | 0x10 : @payloadFlags & ~0x10
      end
    end
    
    def discardBlockIfNotProcessed?(type = :payload)
      case type 
      when :payload: 
          @payloadFlags & 0x10 == 1 
      end
    end
    
    def forwardedBlockWithoutProcessing=(set, type = :payload)
      case type 
      when :payload: 
          @payloadFlags = set ? @payloadFlags | 0x20 : @payloadFlags & ~0x20
      end
    end
    
    def forwardedBlockWithoutProcessing?(type = :payload)
      case type 
      when :payload: 
          @payloadFlags & 0x20 == 1 
      end
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

      # Bundle Payload Block
      data << 1
      data << @payloadFlags
      data << Sdnv.encode(@payload.length)
      data << @payload
      return data
    end

    def marshal_load(bundleStr)     
      @bundleId=@@bundleCount+=1
      @state = PrimaryBundleBlock.new(self)
      io=StringIO.new(bundleStr)
      self.parse(io)
      return self
    end

    def marshal_dump
      return self.to_s
    end

    def fragmentNParts(n=2)
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
      # FIXME: this should be done more efficiently
      self.to_s.length
      #return @payload.length + 50
    end

    def Bundle.reassemble(fragment1, fragment2)
      if not fragment1.fragment? or not fragment2.fragment?
	raise ProtocolError, "Bundles that are not fragments cannot be reassembled"
      end
      if fragment1.fragmentOffset > fragment2.fragmentOffset
	fragment1, fragment2 = fragment2, fragment1
      end
      if fragment1.fragmentOffset + fragment1.payload.length < fragment2.fragmentOffset
	raise ProtocolError, "Cannot reassemble the fragments. There are missing bytes between them"
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
	scheme = self.send(eid).scheme
	ssp = self.send(eid).ssp
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

    # Calculate the size of the "headers" (the primary block, extension
    # blocks, and the headers of the payload block). This is (roughly) the
    # stuff that needs to be repeated in all the fragments. As some
    # blocks only need to appear in one fragment and some SDNVs may become
    # smaller we err a bit on the high side here.
    
    def headerSize
      self.bundleSize - @payload.length
    end

    # Returns two bundles. The first is no greater that targetSize bytes
    # containg first bytes of this
    # bundle, the second bundle contains the rest.

    def doFragment(targetSize)
      offset = targetSize-headerSize
      if offset <= 0
	raise ProtocolError, "Cannot fragment to target size #{targetSize} bytes, as the header requires #{headerSize} bytes."
      end

      fragment1 = self.clone
      fragment2 = self.clone
      fragment1.payload = @payload[0,offset]
      fragment2.payload = @payload[offset..-1]
      fragment1.fragment = fragment2.fragment = true
      if not self.fragment?
	fragment1.fragmentOffset = 0
	fragment2.fragmentOffset = offset
	fragment1.aduLength = fragment2.aduLength = @payload.length
      else
	# If we are fragmenting a bundle that is already a fragment the total
	# ADU is unchanged and the offset of the first fragment is the same as
	# the old offset. Only the offset of the second fragment is changed.
	fragment2.fragmentOffset = offset + @fragmentOffset
      end

      return fragment1, fragment2

    end

  end

  class State

    attr_accessor :bundle

    def initialize(bundle)
      @bundle = bundle
    end

  end

  class PrimaryBundleBlock < State
    include GenParser

    def initialize(bundle)
      super(bundle)

      defField(:version, :length => 1, :decode => GenParser::NumDecoder,
	       :condition => lambda {|version| SUPPORTED_VERSIONS.include?(version)},
	       :handler => :defineFields)

    end

    def defineFields(version)
      @bundle.version = version
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
	       :object => @bundle,
	       :handler => :blockLength=)
      if version == 4
	defField(:destSchemeOff, :length => 2, :decode => GenParser::NumDecoder,
		 :object => @bundle,
		 :handler => :destSchemeOff=)
	defField(:destSspOff, :length => 2, :decode => GenParser::NumDecoder,
		 :object => @bundle,
		 :handler => :destSspOff=)
	defField(:srcSchemeOff, :length => 2, :decode => GenParser::NumDecoder,
		 :object => @bundle,
		 :handler => :srcSchemeOff=)
	defField(:srcSspOff, :length => 2, :decode => GenParser::NumDecoder,
		 :object => @bundle,
		 :handler => :srcSspOff=)
	defField(:repToSchemeOff,:length => 2, :decode => GenParser::NumDecoder,
		 :object => @bundle,
		 :handler => :repToSchemeOff=)
	defField(:repToSspOff, :length => 2, :decode => GenParser::NumDecoder,
		 :object => @bundle,
		 :handler => :repToSspOff=)
	defField(:custSchemeOff, :length => 2, :decode => GenParser::NumDecoder,
		 :object => @bundle,
		 :handler => :custSchemeOff=)
	defField(:custSspOff, :length => 2, :decode => GenParser::NumDecoder,
		 :object => @bundle,
		 :handler => :custSspOff=)
	defField(:creationTimestamp, :length => 4, 
		 :object => @bundle,
		 :decode => GenParser::NumDecoder, 
		 :handler => :creationTimestamp=)
	defField(:creationTimestampSeq, :length => 4, 
		 :object => @bundle,
		 :decode => GenParser::NumDecoder, 
		 :handler => :creationTimestampSeq=)
	defField(:lifetime, :length => 4, :decode => GenParser::NumDecoder,
		 :object => @bundle,
		 :handler => :lifetime=)
      elsif version == 5
	defField(:destSchemeOff, :decode => GenParser::SdnvDecoder,
		 :object => @bundle,
		 :handler => :destSchemeOff=)
	defField(:destSspOff, :decode => GenParser::SdnvDecoder,
		 :object => @bundle,
		 :handler => :destSspOff=)
	defField(:srcSchemeOff, :decode => GenParser::SdnvDecoder,
		 :object => @bundle,
		 :handler => :srcSchemeOff=)
	defField(:srcSspOff, :decode => GenParser::SdnvDecoder,
		 :object => @bundle,
		 :handler => :srcSspOff=)
	defField(:repToSchemeOff,:decode => GenParser::SdnvDecoder,
		 :object => @bundle,
		 :handler => :repToSchemeOff=)
	defField(:repToSspOff, :decode => GenParser::SdnvDecoder,
		 :object => @bundle,
		 :handler => :repToSspOff=)
	defField(:custSchemeOff, :decode => GenParser::SdnvDecoder,
		 :object => @bundle,
		 :handler => :custSchemeOff=)
	defField(:custSspOff, :decode => GenParser::SdnvDecoder,
		 :object => @bundle,
		 :handler => :custSspOff=)
	defField(:creationTimestamp, 
		 :object => @bundle,
		 :decode => GenParser::SdnvDecoder, 
		 :handler => :creationTimestamp=)
	defField(:creationTimestampSeq, 
		 :object => @bundle,
		 :decode => GenParser::SdnvDecoder, 
		 :handler => :creationTimestampSeq=)
	defField(:lifetime, :decode => GenParser::SdnvDecoder,
		 :object => @bundle,
		 :handler => :lifetime=)
      end
      defField(:dictLength, :decode => GenParser::SdnvDecoder,
	       :object => @bundle,
	       :handler => :dictLength=,
	       :block => lambda {|len| defField(:dict, :length => len)})
      defField(:dict, :handler => :dict=)
      # These fields are only enabled (ignore => false) when the
      # corresponding flags are set
      defField(:fragmentOff, :ignore => true, :handler => :fragmentOff=,
	       :decode => GenParser::SdnvDecoder,
	       :object => @bundle)
      defField(:totalADUlen, :ignore => true, :handler => :totalADULen=,
	       :decode => GenParser::SdnvDecoder,
		 :object => @bundle)
    end

    def procFlags=(flags)
      #TODO interpret flags
      @bundle.procFlags = flags
    end

    def cosFlags=(flags)
      #TODO interpret flags
      @bundle.cosFlags = flags
    end

    def srrFlags=(flags)
      #TODO interpret flags
      @bundle.srrFlags = flags
    end

    def dict=(dict)
      sio = StringIO.new(dict)

      @bundle.destEid = EID.new
      @bundle.srcEid = EID.new
      @bundle.reportToEid = EID.new
      @bundle.custodianEid = EID.new

      sio.pos = @bundle.destSchemeOff
      @bundle.destEid.scheme = sio.gets(0.chr).strip
      sio.pos = @bundle.destSspOff
      @bundle.destEid.ssp = sio.gets(0.chr).strip

      sio.pos = @bundle.srcSchemeOff
      @bundle.srcEid.scheme = sio.gets(0.chr).strip
      sio.pos = @bundle.srcSspOff
      @bundle.srcEid.ssp = sio.gets(0.chr).strip

      sio.pos = @bundle.repToSchemeOff
      @bundle.reportToEid.scheme = sio.gets(0.chr).strip
      sio.pos = @bundle.repToSspOff
      @bundle.reportToEid.ssp = sio.gets(0.chr).strip

      sio.pos = @bundle.custSchemeOff
      @bundle.custodianEid.scheme = sio.gets(0.chr).strip
      sio.pos = @bundle.custSspOff
      @bundle.custodianEid.ssp = sio.gets(0.chr).strip

    end

    def readData(io)
      oldPos = io.pos
      begin
	self.parse(io)

      rescue InputTooShort => detail
	io.pos = oldPos
	raise
      end

      # The next thing to do is parse some other kind of block
      return AnyBlock.new(@bundle)
    end

  end

  # This state 

  class AnyBlock < State

    def initialize(bundle)
      super(bundle)
    end

    def readData(io)
      blockType = io.getc
      case blockType
	# Currently we only know one type of block
      when 1
	return BundlePayloadBlock.new(@bundle)
      else
	raise ProtocolError, "Unknown block type #{blockType}"
      end
    end
  end

  class BundlePayloadBlock < State
    include GenParser

    def initialize(bundle)
      super(bundle)

      if @bundle.version == 4
	defField(:procFlags, :length => 1, :decode => GenParser::NumDecoder,
		 :handler => :procFlags=)
      elsif @bundle.version == 5
	defField(:procFlags, :decode => GenParser::SdnvDecoder,
		 :handler => :procFlags=)
      end
      defField(:plblockLength, :decode => GenParser::SdnvDecoder,
	       :object => @bundle,
	       :block => lambda {|len| defField(:payload, :length => len)})
      defField(:payload, :handler => :payload=, :object => @bundle)

    end

    def procFlags=(flags)
      #TODO: interpret flags
      @bundle.payloadFlags = flags
    end

    def readData(io)
      oldPos = io.pos
      begin
	self.parse(io)
      rescue InputTooShort => detail
	io.pos = oldPos
	raise
      end
      return AnyBlock.new(@bundle)
    end
  end

end # module Bundling

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
      :payloadFlags, :payloadLength, :payload,
      :bytesToRead, :queue

    attr_reader :state, :bundleId
    


    @@bundleCount=0

    def initialize(payload=nil, destEid=nil, srcEid=nil, reportToEid=nil,
		  custodianEid=nil)
      @bundleId=@@bundleCount+=1
      @payload = payload
      @version = 4
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

    def to_s
      data = ""
      data << @version # For now we implement only version 4 like DTN2
      data << @procFlags
      data << @cosFlags
      data << @srrFlags
      pbb = ""
      dict = buildDict()
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

  end

  class State

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
      if version == 4
	defField(:procFlags, :length => 1, :decode => GenParser::NumDecoder,
		 :handler => :procFlags=)
	defField(:cosFlags, :length => 1, :decode => GenParser::NumDecoder,
		 :handler => :cosFlags=)
	defField(:srrFlags, :length => 1, :decode => GenParser::NumDecoder,
		 :handler => :srrFlags=)
	defField(:blockLength, :decode => GenParser::SdnvDecoder,
		 :object => @bundle,
		 :handler => :blockLength=)
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
	#TODO: fields for version 5
      end
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
      defField(:blockLength, :decode => GenParser::SdnvDecoder,
	       :object => @bundle, :handler => :payloadLength=,
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

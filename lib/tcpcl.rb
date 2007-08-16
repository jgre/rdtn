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

# TCP convergence layer

require "socket"
require "monitor"
require "rdtnlog"
require "rdtnerror"
require "configuration"
require "cl"
require "sdnv"
require "queue"
require "rdtnevent"
require "eidscheme"
require "stringio"
require "genparser"
require "queuedio"

MAGIC = "dtn!"
TCPCL_VERSION = 3

DATA_SEGMENT = 0x1
ACK_SEGMENT = 0x2
REFUSE_BUNDLE = 0x3
KEEPALIVE = 0x4
SHUTDOWN = 0x5

TCPCLPORT=4557 # FIXME


module TCPCL

  class InvalidTCPCLTypeCode < ProtocolError
    def initialize(code)
      super("Invalid TCPCL type code #{code}")
    end
  end

  class OverwritingBundle < ProtocolError
    def initialize
      super("Receiving new bundle while another one is still inflight.")
    end
  end
  
  # Base class for the states of the TCP convergence layer protocol parser.
  
  class State
    
    def initialize(tcpLink)
      @@log=RdtnLogger.instance()
      @tcpLink = tcpLink
    end
    
  end
  
  # A TCP connection has been established on a link. A contact header needs to 
  # be exchanged
  
  class ConnectedState < State
    include GenParser
    
    def initialize(tcpLink)
      super(tcpLink)
      
      defField(:magic, :length => 4, 
	       :condition => lambda {|data| data == MAGIC})
      defField(:version, :length => 1, :decode => GenParser::NumDecoder,
	       :condition => lambda {|data| data == TCPCL_VERSION})
      defField(:flags, :length => 1, :decode => GenParser::NumDecoder,
	       :handler => :flags=)
      defField(:keepaliveInterval, :length => 2,:handler => :keepaliveInterval=,
	       :decode => GenParser::NumDecoder)
      defField(:eidLength, :decode => GenParser::SdnvDecoder,
	       :block => lambda {|data| defField(:localEid, :length => data)})
      defField(:localEid, 
	       :block => lambda {|eid| @tcpLink.remoteEid = EID.new(eid)})
    end
    
    def flags=(flags)
      # enable acks if both partners support it
      @tcpLink.connection[:acks]  = @tcpLink.options[:acks] && (flags & 0x1 == 1)
      
      # enable nacks if both partners support it and acks are enabled
      @tcpLink.connection[:nacks] = @tcpLink.connection[:acks] &&
                                    @tcpLink.options[:nacks] && 
                                    (flags & 0x4 == 1)
      
      # enable reactive Fragmentation if both partners support it
      @tcpLink.connection[:reactiveFragmentation] = 
                                    @tcpLink.options[:reactiveFragmentation] && 
                                    (flags & 0x2 == 1)
      return nil
    end
    
    def keepaliveInterval=(interval)
      # FIXME Pass interval to link object
      return nil
    end
    

    # Parse the received contact header. Io is a StringIO object whose current
    # position is expected to be at the beginning of the contact header. When
    # parsing is successful the current position is at the end of the contat
    # header. In case of an error an exeption is raised and the current position
    # where it was before this method was executed. Returns the next state
    # (ContactEstablishedState).

    def readData(io)
      # remember this so we can go back here in case of a recoverable error
      oldPos = io.pos
      begin
	self.parse(io)
      rescue InputTooShort => detail
	io.pos = oldPos
	raise
      end
      
      EventDispatcher.instance().dispatch(:routeAvailable, @tcpLink, 
					  @tcpLink.remoteEid)
      return ContactEstablishedState.new(@tcpLink)
    end
  end
  
  # The connection is established and the contact header has been exchanged.
  # Bundles can be sent and received.
  # This state only parses the first four bits of the received data to determine
  # the type code. The type code determines the next state which parses the actual
  # input. All states except ErrorState, DisconnectedState, and ShutdownState get
  # back to this state after successfully parsing a segment.
  
  class ContactEstablishedState < State
    
    def initialize(tcpLink)
      super(tcpLink)
    end
    
    # Parse the type code from the incoming data. Io is a StringIO object
    # expected to be at the beginning of a segment. The current position is not
    # modified. Returns the next state.

    def readData(io)
      if io.eof?
	raise InputTooShort, 1
      end
      typeCode = (io.getc & 0xf0) >> 4 # First 4 bits
      nextState = case typeCode
                  when DATA_SEGMENT: ReceivingState.new(@tcpLink)
                  when ACK_SEGMENT: AckState.new(@tcpLink)
                  when REFUSE_BUNDLE: RefuseState.new(@tcpLink)
                  when KEEPALIVE: KeepaliveState.new(@tcpLink)
                  when SHUTDOWN: ShutdownState.new(@tcpLink)
                  else raise InvalidTCPCLTypeCode, typeCode
                  end
      io.pos = io.pos - 1 # We still need this byte
      
      return nextState
    end
    
  end
    
  # The connection has been established, the contact header was exchanged and
  # data segment is received. This class handles the reading of data from the
  # remote endpoint. The data of the actual bundle is passed to TCPLink
  # instance.
  
  class ReceivingState < State
    include GenParser
    attr_accessor :contentLength
    
    def initialize(tcpLink)
      super(tcpLink)
      
      defField(:flags, :length => 1, :block => lambda do |data| 
                 @sFlag = data[0] & 0x2 # The 7th bit
                 @eFlag = data[0] & 0x1 # The last bit
               end)
      defField(:contentLength, :decode => GenParser::SdnvDecoder,
	       :handler => :contentLength=,
	       :block => lambda {|data| defField(:content, :length => data)})
      defField(:content, :decode => GenParser::NullDecoder, 
	       :handler => :bundleData)
    end
    
    def bundleData(data = nil)
      @tcpLink.handleBundleData(@sFlag != 0, @eFlag != 0, @contentLength)
    end
    
    # Parse incoming data segments. Io is a StringIO object expected to be
    # positioned at the start of the data segment. If parsing is successful, the
    # current position is at the end of the data segment. If an error occurs,
    # the current position is returned to the beginning of the segment. The
    # methods returns the next state (ContactEstablishedState).

    def readData(io)
      oldPos = io.pos
      begin
	self.parse(io)
      rescue InputTooShort => detail
	io.pos = oldPos
	raise
      end
      return ContactEstablishedState.new(@tcpLink)
    end
    
  end
  
  class AckState < State
    include GenParser
    
    def initialize(tcpLink)
      super(tcpLink)
      
      defField(:flags, :length => 1,
               :condition => lambda {|data| data[0] == (ACK_SEGMENT << 4)})
      
      defField(:recievedLength, :decode => GenParser::SdnvDecoder,
               :handler => :recievedLength)
    end
    
    # TODO
    # - Store number of transmitted bytes for bundle and link. The link
    #   must be remembered when a transfer should be continued after a
    #   connection broke and if reactive fragmentation is not enabled(I guess).
    # - Remove bytes from bundle if reactive fragmentation is enabled. 
    
    def recievedLength(length)
      # @tcpLink.removeAcknowledgedPayload(length)
    end 
    
    def readData(io)
      oldPos = io.pos
      begin
	self.parse(io)
      rescue InputTooShort => detail
	io.pos = oldPos
	raise
      end
      return ContactEstablishedState.new(@tcpLink)
    end
    
  end
  
  class RefuseState < State
    
    def initialize(tcpLink)
      super(tcpLink)
    end
    
    def readData(io)
      # TODO
      io.read
      return self
    end
    
  end
  
  class KeepaliveState < State
    
    def initialize(tcpLink)
      super(tcpLink)
    end
    
    def readData(io)
      io.read
      return self
    end
    
  end
  
  class ShutdownState < State
    
    def initialize(tcpLink)
      super(tcpLink)
    end
    
    def readData(io)
      io.read
      return self
    end
    
  end
  
  class ErrorState < State
    
    def initialize(tcpLink)
      super(tcpLink)
    end
    
    def readData(io)
      io.read
      return self
    end
    
  end
  
  class DisconnectedState < State
    
    def initialize(tcpLink)
      super(tcpLink)
    end
    
    def readData(io)
      io.read
      return self
    end
    
  end
  
  # TCPLink implements the TCP convergence layer protocol. Objects of this class
  # maintain the state of a TCP CL connection (state is encapsulated in the
  # subclasses of State which also implement the reception of data) and handle
  # the sending of bundles and the signalling of incoming bundles to the bundle
  # layer.

  class TCPLink < Link
    
    include QueuedSender
    include QueuedReceiver
    include MonitorMixin
    @@log=RdtnLogger.instance()
    attr_accessor :remoteEid
    attr_accessor :connection # holds variables for negotiated options    
    attr_accessor :options
    
    # Build a new link from existing socket (after accept). The initial state is
    # DisconnectedState. If a connected socket was passed, a contact header is
    # send and the socket is watched for incoming data.
    
    def initialize(sock = nil)
      super()
      queuedReceiverInit(sock)
      queuedSenderInit(sock)
      
      @segmentLength = 32768
      @options = {}
      @options[:acks]  = true
      @options[:nacks] = true
      @options[:reactiveFramentation] = true
      
      @connection = {}
      @connection[:acks]  = false
      @connection[:nacks] = false
      @connection[:reactiveFragmentation] = false
      
      self.state = DisconnectedState.new(self)
      @currentBundle = RdtnStringIO.new  
      
      if sock
	watch()
	sendContactHeader()
	@@log.debug("TCPLink::initialize: watching new socket")
      end
      
    end
    
    # Open the link, i.e. establish a TCP connection. Name is a string by which
    # the link is identifier (e.g. 'tcp0'). Options are passed as string:
    # [--type, -t] ONDEMAND (link is created when data is to be sent (FIXME))
    #              ALWAYSON (link is immediately created and kept opnen
    # [--nexthop, -n] 
    
    def open(name, options)
      self.name = name
      port = 0
      host = ""
      
      if options.has_key?(:host)
	host = options[:host]
      end
      if options.has_key?(:port)
	port = options[:port]
      end
      if options.has_key?(:type)
	type = options[:type]
      end
      
      @sendSocket.close if @sendSocket and not @sendSocket.closed?
      @receiveSocket.close if @receiveSocket and not @receiveSocket.closed?
      
      connect(host, port)
    end
    
    def close(wait = nil)
      #sendShutdown
      sdThread = senderThread { sendShutdown }
      #sdThread.join(1) #FIXME: Make this limit configurable
      #sdThread.kill
      @@log.debug("TCPLINK::close -- closing socket #{@s}")
      # Now close the thread
      super
      @sendSocket.close if @sendSocket and not @sendSocket.closed?
      @receiveSocket.close if @receiveSocket and not @receiveSocket.closed?
    end
    
    # Transmit a bundle over the TCP CL.
    #--
    # FIXME: check if the link is in an error or disconnected state before
    # sending.
    
    def sendBundle(bundle)
      
      # Chop the bundle into segments
      bndQ = RdtnStringIO.new(bundle.to_s)
      while not bndQ.eof?
	buf = ""
	flags = 0
	flags = 0x2 if @sendQueue.pos == 0

	data = bndQ.read(@segmentLength)

	if @sendQueue.eof?
	  flags = flags | 0x1
	end 

	return unless data 

	buf << ((DATA_SEGMENT << 4) | flags)
	buf << Sdnv.encode(data.length)
	buf << data
	sendQueueAppend(buf)
      end

      senderThread { doSend }
    end

    def handleBundleData(startSegment, endSegment, length)
      if @currentBundle.size > 0 and startSegment
        raise OverwritingBundle
      end
      # Remove the bundle data from the incoming queue and append it to the
      # current bundle data queue
      data = @readQueue.read(length)
      if data.length < length
	raise InputTooShort, 1
      end
      @currentBundle.enqueue(data)
      EventDispatcher.instance().dispatch(:bundleData, @currentBundle, 
					               endSegment, 
						       self)
      if endSegment
        @@log.debug("TCPLink::handle_bundle_data Bundle is complete")
        # We take a new object for the next bundle. The bundle parser must take
        # care of closing the old one.
        @currentBundle = RdtnStringIO.new
      end
      
      # TODO when acks should be send (accumulation)? for now after every 
      # recieved segment  
      if @connection[:acks]
        sendAck(length)
      end
    end

    protected

    def state=(newState)
      synchronize do
	@state = newState
      end
    end

    private 

    def connect(host, port)
      receiverThread(host, port) do |h, p| 
	@sendSocket = @receiveSocket = TCPSocket.new(h, p) 
	watch()
	sendContactHeader()
      end
    end

    # Start listener thread waiting for data and change the state to 
    # ConnectedState.

    def watch
      self.state = ConnectedState.new(self)
      receiverThread { read }
    end

    # Loop endlessly reading data from the socket. The link is closed (causing 
    # the thread to terminate) when an error occurs or the connection is closed.
    
    def read
      begin
	doRead do |input|

	  # Process the currently queued data to the current state handler. Keep
	  # parsing until the queue is empty or the processor raises an
	  # exception to tell us to wait for more data.

	  begin

	    while not input.eof?
	      self.state = @state.readData(input)
	    end

	  rescue InputTooShort => detail
	    @@log.info("Input too short need to read 
		       #{detail.bytesMissing} (#{input.length} given)")
	    self.bytesToRead = detail.bytesMissing
	  end
	end

      rescue SystemCallError, IOError    # lost TCP connection 
	@@log.warn("TCPLink::whenReadReady::recvfrom " + $!)
      end
      # If we are here, doRead hit an error or the link was closed.
      close
    end
    
    # Send the data over the current socket in a new thread
    def send(data)
      sendQueueAppend(data)
      senderThread { doSend }
    end

    # Create the contact header and spawn a thread that sends it.
    def sendContactHeader
      hdr = ""
      hdr << MAGIC
      hdr << TCPCL_VERSION
      
      # FIXME
      # 00000001: Request acknowledgement of bundle segments.
      # 00000010: Request enabling of reactive fragmentation.  
      # 00000100: Indicate support for negative acknowledgements.  
      flags = 0
      flags = flags | 0x1 if @options[:acks]   
      flags = flags | 0x2 if @options[:reactiveFragmentation]      
      flags = flags | 0x4 if @options[:nacks] && @options[:acks]
      
      hdr << flags
      keepaliveInterval = 120
      # use array#pack to get a short in network byte order
      hdr << [keepaliveInterval].pack('n')
      hdr << Sdnv.encode(RdtnConfig::Settings.instance.localEid.length)
      hdr << RdtnConfig::Settings.instance.localEid
      
      send(hdr)
    end
    
    # Generate an ACK message for +length+ bytes and start a thread to send it.
 
    def sendAck(length)
      buf = ""
      buf << (ACK_SEGMENT << 4)
      buf << Sdnv.encode(length)
      senderThread(buf) { |buffer| send(buffer) }
    end
    
    # Cleanly terminate a TCP CL connection. Blocks the current thread.
    
    def sendShutdown
      buf = ""
      flags = 0
      buf << ((SHUTDOWN << 4) | flags)
      buf << 0 # I don't care about the reason for now
      send(buf)
    end
    
  end
  
  
  # one interface can generate many links (through accepting new connections)
  
  class TCPInterface < Interface
    
    attr_reader :links
    @s
   
    @@log=RdtnLogger.instance()

    def initialize(name, options)
      
      self.name = name
      host = "localhost"
      port = TCPCLPORT          # default port
     
      @links = []      

      if options.has_key?(:host)
	host = options[:host]
      end
      if options.has_key?(:port)
	port = options[:port]
      end

      @@log.debug("Building TCP interface with port=#{port} and hostname=#{host}")
      
      @s = TCPServer.new(host,port)
      # register this socket
      listenerThread { whenAccept }
    end
    
    def whenAccept()
      while true
	#FIXME deal with errors
	@links << TCPLink.new(@s.accept())
	@@log.debug("created new link #{@link.object_id}")
      end
    end
    
    def close
      super
      if not @s.closed?
        @s.close
      end
    end
    
  end
  
end # module TCPCL
     
regCL(:tcp, TCPCL::TCPInterface, TCPCL::TCPLink)

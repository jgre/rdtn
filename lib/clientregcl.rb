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


require "stringio"
require "socket"
require "rdtnlog"
require "clientapi"
require "queue"
require "rdtnevent"
require "rdtnerror"
require "bundle"
require "cl"
require "internaluri"
require "queuedio"

module AppIF

  class AppProxy < Link

    include QueuedSender
    include QueuedReceiver

    @@log=RdtnLogger.instance()
    attr_accessor :remoteEid, :registration

    def initialize(sock = nil)
      super()
      queuedReceiverInit(sock)
      queuedSenderInit(sock)
      @remoteEid = ""
      if sock
	receiverThread { read }
	@@log.debug("AppProxy::initialize: watching new socket")
      end
    end
    
    def close(wait = nil)
      @@log.debug("AppProxy::close -- closing socket #{@s}")
      @sendSocket.close if not @sendSocket.closed?
      @receiveSocket.close if not @receiveSocket.closed?
      super
    end

    def sendBundle(bundle)
      @@log.debug("AppProxy::sendBundle: -- Delivering bundle to #{bundle.destEid}")
      sendPDU(POST, {:uri => "rdtn:bundles/#{bundle.bundleId}/",
      		     :bundle => bundle})
    end


    private
    def read
      begin
	doRead do |input|
	  while not input.eof?
	    wait = processData(input)
	    break if wait
	  end
	end
      rescue SystemCallError    # lost TCP connection 
      @@log.error("AppProxy::read" + $!)
      end
      # If we are here, doRead hit an error or the link was closed.
      self.close()              
    end

    def processData(data)
      oldPos = data.pos
      typeCode = data.getc
      begin
	args=Marshal.load(data)
      rescue ArgumentError => err
	data.pos = oldPos
	return true
      end

      begin
	uri = args[:uri]
	RdtnLogger.instance.debug("AppProxy #{@name} process: #{uri}")
	ri = RequestInfo.new(typeCode, self)
	store = Storage.instance
	responseCode, response = PatternReg.resolve(uri, ri, store, args)
	sendPDU(responseCode, response)
      rescue ProtocolError => err
	RdtnLogger.instance.warn("AppProxy #{@name} error: #{err}")
	sendPDU(STATUS, {:uri => uri, :status => 400, :message => err.to_s })
      end

      return false
    end

    def send(buf)
      sendQueueAppend(buf)
      senderThread { doSend }
    end

    def sendPDU(type, pdu)
      buf="" + type.chr() + Marshal.dump(pdu)
      send(buf)
    end

  end

  class AppInterface <Interface

    @@log=RdtnLogger.instance()

    def initialize(name, options = {})
      host = "localhost"
      port = RDTNAPPIFPORT

      if options.has_key?(:host)
	host = options[:host]
      end
      if options.has_key?(:port)
	port = options[:port]
      end

      @@log.debug("Building client interface with port=#{port} and hostname=#{host}")

      @s = TCPServer.new(host,port)
      # register this socket
      listenerThread { whenAccept }
    end

    def close
      if socketOK?
	@s.close
      end
    end

    private
    def socketOK?
      (@s.class.to_s=="TCPSocket") && !@s.closed?()
    end

    def whenAccept()
      while true
	@@log.debug("AppInterface::whenAccept")
	#FIXME deal with errors
	@link= AppProxy.new(@s.accept())
	@@log.debug("created new AppProxy #{@link.object_id}")
      end
    end

  end


end # module AppIF


regCL(:client, AppIF::AppInterface, AppIF::AppProxy)

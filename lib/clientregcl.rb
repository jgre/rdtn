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

    attr_accessor :remoteEid, :registration

    def initialize(sock = nil)
      super()
      queuedReceiverInit(sock)
      queuedSenderInit(sock)
      @remoteEid = ""
      if sock
	receiverThread { read }
	rdebug(self, "AppProxy::initialize: watching new socket")
      end
    end
    
    def close(wait = nil)
      rdebug(self, "AppProxy::close -- closing socket #{@s}")
      @sendSocket.close if not @sendSocket.closed?
      @receiveSocket.close if not @receiveSocket.closed?
      super
    end

    def sendBundle(bundle)
      rdebug(self, "AppProxy::sendBundle: -- Delivering bundle to #{bundle.destEid}")
      sendPDU(POST, {:uri => "rdtn:bundles/#{bundle.bundleId}/",
      		     :bundle => bundle})
    end

    def sendEvent(uri, *args)
      sendPDU(POST, {:uri => uri, :args => args})
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
      rerror(self, "AppProxy::read" + $!)
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
	rdebug(self, "AppProxy #{@name} process: #{uri}")
	ri = RequestInfo.new(typeCode, self)
	store = RdtnConfig::Settings.instance.store
	responseCode, response = PatternReg.resolve(uri, ri, store, args)
	sendPDU(responseCode, response)
      rescue ProtocolError => err
	rwarn(self, "AppProxy #{@name} error: #{err}")
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

    def initialize(name, options = {})
      host = "localhost"
      port = RDTNAPPIFPORT

      if options.has_key?(:host)
	host = options[:host]
      end
      if options.has_key?(:port)
	port = options[:port]
      end

      rdebug(self, "Building client interface with port=#{port} and hostname=#{host}")

      @s = TCPServer.new(host,port)
      # register this socket
      listenerThread { whenAccept }
    end

    def close
      super
      @s.close if socketOK?
    end

    private
    def socketOK?
      return (not @s.closed?)
    end

    def whenAccept()
      while true
	#FIXME deal with errors
	@link= AppProxy.new(@s.accept())
	rdebug(self, "created new AppProxy #{@link.object_id}")
      end
    end

  end


end # module AppIF


regCL(:client, AppIF::AppInterface, AppIF::AppProxy)

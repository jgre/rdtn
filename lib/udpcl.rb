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
# $Id$

# UDP convergence layer

require "socket"
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

MAX_UDP_PACKET = 65535
UDPCLPORT = 4557

module UDPCL

  class UDPLink < Link
    attr_accessor :remoteEid, :maxBundleSize
    include QueuedSender

    def initialize(sock = nil)
      super()
      queuedSenderInit(sock)
    end

    def open(name, options)
      self.name = name
      port = UDPCLPORT 
      host = nil 

      if options.has_key?(:host)
	host = options[:host]
      end
      if options.has_key?(:port)
	port = options[:port]
      end
      if options.has_key?(:maxBundleSize)
	@maxBundleSize = options[:maxBundleSize]
      end

      if socketOK?
	close
      end
      @sendSocket = UDPSocket.new
      # For UDP this operation does not block, so we do it without thread
      @sendSocket.connect(host, port)
    end

    def close(wait = nil)
      super
      RdtnLogger.instance.debug("UDPLink::close")
      if socketOK?
	@sendSocket.close
      end
    end

    def socketOK?
      return (@sendSocket and not @sendSocket.closed?)
    end
      
    def sendBundle(bundle)
      sendQueueAppend(bundle.to_s)
      senderThread { doSend }
    end

  end

  class UDPInterface < Interface

    include QueuedReceiver

    def initialize(name, options)
      self.name = name
      host = nil
      port = UDPCLPORT

      if options.has_key?(:host)
	host = options[:host]
      end
      if options.has_key?(:port)
	port = options[:port]
      end

      RdtnLogger.instance.debug("Building UDP interface with port=#{port} and hostname=#{host}")
      sock = UDPSocket.new
      sock.bind(host, port)
      queuedReceiverInit(sock)
      @readQueueChunkSize = MAX_UDP_PACKET
      listenerThread { read }
    end
    
    def close
      super
      if not @receiveSocket.closed?
        @receiveSocket.close
      end
    end
    
    private
    def read
      begin
	doRead do |input|
	  EventDispatcher.instance().dispatch(:bundleData, input, true, self)
	end
      rescue SystemCallError
	@@log.error("UDPLink::whenReadReady::recvfrom" + $!)
      end
      # If we are here, doRead hit an error or the link was closed.
      self.close()              
    end
    
  end

end #module UDPCL

regCL(:udp, UDPCL::UDPInterface, UDPCL::UDPLink)

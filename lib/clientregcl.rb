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
require "queue"
require "rdtnevent"
require "rdtnerror"
require "bundle"
require "cl"
require "queuedio"

module AppIF

  class AppProxy < Link

    attr_accessor :remoteEid, :registration

    def initialize(config, evDis, &handler)
      super(config, evDis)
      @remoteEid = @config.localEid
      @handler   = handler
    end
    
    def sendBundle(bundle)
      rdebug(self, "AppProxy::sendBundle: -- Delivering bundle to #{bundle.destEid}")
      @handler.call(bundle)
    end

  end

  class AppLink < Link

    include QueuedSender
    include QueuedReceiver

    def initialize(config, evDis, daemon, sock)
      super(config, evDis)
      @daemon = daemon
      queuedReceiverInit(sock)
      queuedSenderInit(sock)
      receiverThread { read }
      rdebug(self, "AppLink::initialize: watching new socket")
    end
    
    def close(wait = nil)
      rdebug(self, "AppProxy::close -- closing socket #{@s}")
      @sendSocket.close if not @sendSocket.closed?
      @receiveSocket.close if not @receiveSocket.closed?
      super
    end

    def sendBundle(bundle)
      sendPDU(:bundle, bundle)
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

    def sendBundle(msgId, bundle)
      @daemon.sendBundle(bundle)
      [:ok, nil]
    end

    def sendDataTo(msgId, *args)
      @daemon.sendDataTo(*args)
      [:ok, nil]
    end

    def deleteBundle(msgId, bundleId)
      @config.store.deleteBundle(bundleId)
      [:ok, nil]
    end
    
    def getBundlesMatchingDest(msgId, dest)
      bundles = @config.store.getBundlesMatchingDest(dest)
      [:bundles, bundles]
    end

    def applicationAck(msgId, bundleId)
      bundle = @config.store.getBundle(bundleId)
      @daemon.applicationAck(bundle)
      [:ok, nil]
    end

    def register(msgId, eid)
      @daemon.register(eid) do |bundle|
	sendPDU(:bundles, msgId, [bundle])
      end
      [:ok, nil]
    end

    def unregister(msgId, eid)
      @daemon.unregister(eid)
      [:ok, nil]
    end

    def processData(data)
      oldPos = data.pos
      begin
        args=Marshal.load(data)
      rescue ArgumentError => err
        data.pos = oldPos
        return true
      end

      type  = args[0]
      msgId = args[1]
      rdebug(self, "AppLink #{@name} process: #{type}, MessageId: #{msgId}")
      begin
	retType, ret = self.send(*args)
      rescue => err
        rwarn(self, "AppProxy #{@name} error: #{err}")
	retType, ret = :error, err
	raise
      end
      sendPDU(retType, msgId, ret)
      return false
    end

    def sendBuf(buf)
      sendQueueAppend(buf)
      doSend
      #senderThread { doSend }
    end

    def sendPDU(type, msgId, *pdu)
      sendBuf(Marshal.dump([type, msgId, *pdu]))
    end

  end

  class AppInterface < Interface

    def initialize(config, evDis, name, options = {})
      @config = config
      @evDis  = evDis
      host = "localhost"
      port = RDTNAPPIFPORT

      @daemon = options[:daemon]
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
	@link= AppLink.new(@config, @evDis, @daemon, @s.accept())
	rdebug(self, "created new AppProxy #{@link.object_id}")
      end
    end

  end


end # module AppIF


regCL(:client, AppIF::AppInterface, AppIF::AppProxy)

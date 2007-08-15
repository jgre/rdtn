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


module AppIF

  class AppProxy < Link

    @s
    @@log=RdtnLogger.instance()
    attr_accessor :remoteEid, :registration

    def initialize(socket=0)
      super()
      @s=socket
      @remoteEid = ""
      @queue = RdtnStringIO.new
      @bytesToRead = 1048576
      if(socketOK?())
	watch()
	@@log.debug("AppProxy::initialize: watching new socket")
      end
    end


    def close
      @@log.debug("AppProxy::close -- closing socket #{@s}")
      if socketOK?
	@s.close
      end
      super
    end


    def watch
      receiverThread { whenReadReady }
    end

    def whenReadReady
      while true
	readData=true
	begin
	  data = @s.recv(@bytesToRead)
	rescue SystemCallError    # lost TCP connection 
	  @@log.error("AppProxy::whenReadReady::recvfrom" + $!)

	  readData=false
	end

	readData=readData && (data.length()>0)



	if readData
	  @queue.enqueue(data)

	else
	  @@log.info("AppProxy::whenReadReady: no data read")
	  # unregister socket and generate linkClosed event so that this
	  # link can be removed

	  self.close()              
	  return
	end


	while not @queue.eof?
	  wait = processData(@queue)
	  if wait
	    break
	  end
	end
      end
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

    def socketOK?
      (@s.class.to_s=="TCPSocket") && !@s.closed?()
    end

    def send(buf)
      senderThread(buf) do |buffer|
	if(socketOK?())
	  res=@s.send(buffer, 0)
	end
      end
    end

    def sendPDU(type, pdu)
      buf="" + type.chr() + Marshal.dump(pdu)
      send(buf)
    end


    def sendBundle(bundle)
      @@log.debug("AppProxy::sendBundle: -- Delivering bundle to #{bundle.destEid}")
      sendPDU(POST, {:uri => "rdtn:bundles/#{bundle.bundleId}/",
      		     :bundle => bundle})
    end


  end




  class AppInterface <Interface

    @s
    @@log=RdtnLogger.instance()

    #    def initialize(host = "localhost", port = RDTNAPPIFPORT)
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

    def socketOK?
      (@s.class.to_s=="TCPSocket") && !@s.closed?()
    end

    private
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

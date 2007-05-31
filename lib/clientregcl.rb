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


RDTNAPPIFPORT=7777

require "stringio"
require "socket"
require "event-loop"
require "rdtnlog"
require "clientapi"
require "queue"
require "rdtnevent"
require "rdtnerror"
require "bundle"
require "cl"


module AppIF


  class State

    def initialize(appProxy)
      @@log=RdtnLogger.instance()
      @@log.debug("new state: " + self.class.name)
      @appProxy = appProxy
    end

    def getObj(data, type)
      p data
      input=StringIO.new(data)
      obj=Marshal.load(input)
      p obj
      begin
        if obj.class!=type
          raise ProtocolError, "invalid paramter"
        end
      end
      bytesRead=input.pos()
      @@log.debug("AppIF::getObj -- read #{bytesRead} bytes of class #{obj.class}")
      if obj.class == Bundling::Bundle
	#@@log.debug("AppIF::getObj -- eid #{obj}")
      end
	
      data.consume!(bytesRead)
      return obj
    end


  end

  class ConnectedState < State

    def initialize(appProxy)
      super(appProxy)
    end

    def readData(data)
      begin
        if data.length<1
	  raise InputTooShort, (1) - data.length          
        end
        typeCode=data[0]
        nextState = case typeCode
                    when REG: RegState.new(@appProxy)
                    when UNREG: UnregState.new(@appProxy)
                    when SEND: SendState.new(@appProxy)
                    else raise ProtocolError, "invalid message code"
                    end
        data.consume!(1)
        return nextState, false
      end
    end
  end
  
  
  class DisconnectedState < State
    
    def initialize(appProxy)
      super(appProxy)
    end
    
    def readData(data)
      @tcp_link.queue.consume!(data.length)
      return self, true
    end
    
  end
  
  
  class RegState < State
    
    def initialize(appProxy)
      super(appProxy)
    end
    
    
    def readData(data)
      obj=getObj(data,RegInfo)
      
      # call register...
      puts("register #{obj}")
      @appProxy.remoteEid = EID.new(obj.to_s)
      EventDispatcher.instance().dispatch(:linkCreated, @appProxy)
      EventDispatcher.instance().dispatch(:contactEstablished, @appProxy)
      return ConnectedState.new(@appProxy), false
    end
  end

  class UnregState < State
    
    def initialize(appProxy)
      super(appProxy)
    end

    def readData(data)
      obj=getObj(data,RegInfo)
      
      # call unregister...
      puts("unregister #{obj}")
      return ConnectedState.new(@appProxy), false
    end
  end


  class SendState < State

    def initialize(appProxy)
      super(appProxy)
    end


    def readData(data)
      obj=getObj(data,Bundling::Bundle)
      
      # call send...
      RdtnLogger.instance.debug("Sending bundle from ClientCL to #{obj.destEid}")
      EventDispatcher.instance().dispatch(:bundleParsed, obj)
      return ConnectedState.new(@appProxy), false
    end
  end




  
  class AppProxy < Link
    
    @s
    @@log=RdtnLogger.instance()
    attr_accessor :remoteEid
    
    def initialize(socket=0)
      @s=socket
      @remoteEid = ""
      @queue = Queue.new
      @bytesToRead = 1024
      @state = DisconnectedState.new(self)
      if(socketOK?())
        watch()
        @@log.debug("AppProxy::initialize: watching new socket")
      end
    end

    
    def close
      @@log.debug("AppProxy::close -- closing socket #{@s}")
      @s.ignore_event :readable
      @s.close
    end


    def watch
      @s.extend EventLoop::Watchable
      @s.will_block = false
      @s.on_readable { self.whenReadReady }
      @s.monitor_event :readable
      @state = ConnectedState.new(self)
      EventDispatcher.instance().dispatch(:linkCreated, self)
    end
    
    def whenReadReady
      @@log.debug("AppProxy::whenReadReady #{self.object_id}")
      readData=true
      begin
        data = @s.recvfrom(@bytesToRead)
      rescue SystemCallError    # lost TCP connection 
        @@log.error("AppProxy::whenReadReady::recvfrom" + $!)
        
        readData=false
      end
      
      @@log.debug("AppProxy::whenReadReady: read #{data[0].length} bytes")
      
      readData=readData && (data[0].length()>0)
      
      
      
      if readData
        @queue << data[0]
        
      else
        @@log.error("AppProxyk::whenReadReady: no data read")
        # unregister socket and generate linkClosed event so that this
        # link can be removed
        
        self.close()              
        EventDispatcher.instance().dispatch(:linkClosed, self)
      end
      

      while @queue.length > 0
	# FIXME: cancel connection on protocol error
	@state, wait = @state.readData(@queue)
	if wait
	  break
	end
      end
    end
    
    def socketOK?
      (@s.class.to_s=="TCPSocket") && !@s.closed?()
    end
    
    def send(buf)
      res=-1
      if(socketOK?())
        res=@s.send(buf, 0)
      end
      return res
    end

    def sendPDU(type, pdu)
      buf="" + type.chr() + Marshal.dump(pdu)
      send(buf)
    end


    def sendBundle(bundle)
      @@log.debug("AppProxy::sendBundle: -- Delivering bundle to #{bundle.destEid}")
      sendPDU(DELIVER,bundle)
    end


  end
  
  
  
  
  class AppInterface <Interface
    
    @s
    @@log=RdtnLogger.instance()
    
#    def initialize(host = "localhost", port = RDTNAPPIFPORT)
    def initialize(name, options)
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
      @s.extend EventLoop::Watchable
      @s.will_block = false
      @s.on_readable { self.whenAccept }
      @s.monitor_event :readable
    end
    
    def whenAccept()
      @@log.debug("TCPInterface::whenAccept")
      #FIXME deal with errors
      @link= AppProxy.new(@s.accept())
      @@log.debug("created new AppProxy #{@link.object_id}")
    end
    
    def close
      @s.close
    end
    
  end


end # module AppIF



regCL(:client, AppIF::AppInterface, AppIF::AppProxy)

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

require "socket"
require "event-loop"
require "clientapi"
require "rdtnlog"
require "bundle"
require "stringio"

class RdtnClient
  @s
  attr_reader :bundleHandler

  def initialize()
    @@log=RdtnLogger.instance()    
    @sendBuf = StringIO.new
    @bundleHandler = lambda {}
  end

  def onBundle(&handler)
    @bundleHandler = handler
  end

    def open(host, port)
      @@log.debug("RdtnClient::open -- opening socket #{@s}")
      if(socketOK?())
	close
      end
      #XXX: Doesn't this block?
      @s = TCPSocket.new(host,port)

      watch()
    end

    def close
      @@log.debug("RdtnClient::close -- closing socket #{@s}")
      @s.ignore_event :readable
      if socketOK?
	@s.close
      end
    end

    def watch
      @s.extend EventLoop::Watchable
      @s.will_block = false
      @s.on_readable { self.whenReadReady }
      @s.monitor_event :readable
#      @state = ConnectedState.new(self)
    end

    def whenReadReady
      readData=true
      data=""
      begin
        data = @s.recvfrom(1024)[0]
      rescue SystemCallError    # lost TCP connection 
        @@log.error("RDTNClient::whenReadReady::recvfrom" + $!)
        readData=false
      end
      @@log.debug("TCPLink::whenReadReady: read #{data.length} bytes")

      readData=readData && (data.length()>0)

      if readData
        input=StringIO.new(data[1..-1])
        typeCode=data[0]
        if typeCode == DELIVER
	  bundle = Marshal.load(input)
	  @bundleHandler.call(bundle)
        end
      else
        @@log.info("TCPLink::whenReadReady: no data read")
        # unregister socket and generate linkClosed event so that this
        # link can be removed
        
        self.close()              
        EventDispatcher.instance().dispatch(:linkClosed, self)
      end
    end

    def socketOK?
      (@s.class.to_s=="TCPSocket") && !@s.closed?()
    end

    def send(data)
      res=-1
      @sendBuf.enqueue(data)
      @s.extend EventLoop::Watchable
      @s.monitor_event :writable
      @s.will_block = false
      @s.on_writable do
	if(socketOK?())
	  @@log.debug("RdtnClient::send -- sending #{data.length()} bytes")
	  if not @sendBuf.eof?
	    buf = @sendBuf.read(32768)
	    res=@s.send(buf,0)
	    if res < buf.length
	      @sendBuf.pos -= (buf.length - res)
	    end
	  end
	  if @sendBuf.eof?
	    @s.ignore_event :writable
	  end
	end
      end
      return res
    end

    def sendPDU(type, pdu)
      buf="" + type.chr() + Marshal.dump(pdu)
      send(buf)
    end

    def register(reginfo)
      # FIXME check for correct type of reginfo
      sendPDU(REG, reginfo)
    end

    def unregister(reginfo)
      sendPDU(UNREG, reginfo)
    end

    def sendBundle(bundle)
      sendPDU(SEND, bundle)
    end


end


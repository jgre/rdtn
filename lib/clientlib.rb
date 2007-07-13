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
require "clientapi"
require "rdtnlog"
require "bundle"
require "queue"
require "rerun_thread"

class RdtnClient
  include RerunThread
  @s
  attr_reader :bundleHandler

  def initialize()
    @@log=RdtnLogger.instance()    
    @sendBuf = RdtnStringIO.new
    @bundleHandler = lambda {}
    @threads = []
  end

  def onBundle(&handler)
    @bundleHandler = handler
  end

  def open(host, port)
    @@log.debug("RdtnClient::open -- opening socket #{@s}")
    if(socketOK?())
      close
    end
    connect(host, port)
  end

  def connect(host, port, blocking=true)
    connectBlock = lambda do |h, p| 
      @s = TCPSocket.new(h, p) 
      watch()
    end
    if blocking
      connectBlock.call(host, port)
    else
      @threads << spawnThread(host, port, &connectBlock) 
    end
  end

    def close
      @threads.each   {|thr| thr.kill }
      @@log.debug("RdtnClient::close -- closing socket #{@s}")
      if socketOK?
	@s.close
      end
      EventDispatcher.instance().dispatch(:linkClosed, self)
    end

    def watch
      @threads << spawnThread { self.whenReadReady }
      #      @state = ConnectedState.new(self)
    end

    def whenReadReady
      while true
	readData=true
	data=""
	begin
	  data = @s.recv(1024)
	rescue SystemCallError    # lost TCP connection 
	  @@log.error("RDTNClient::whenReadReady::recvfrom" + $!)
	  readData=false
	end
	@@log.debug("TCPLink::whenReadReady: read #{data.length} bytes")

	readData=readData && (data.length()>0)

	if readData
	  input=RdtnStringIO.new(data[1..-1])
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
	end
      end
    end

    def socketOK?
      (@s.class.to_s=="TCPSocket") && !@s.closed?()
    end

    def send(data)
      @sendBuf.enqueue(data)
      @threads << spawnThread do
	while socketOK? and not @sendBuf.eof?
	  @@log.debug("RdtnClient::send -- sending #{data.length()} bytes")
	  if not @sendBuf.eof?
	    buf = @sendBuf.read(32768)
	    res=@s.send(buf,0)
	    if res < buf.length
	      @sendBuf.pos -= (buf.length - res)
	    end
	  end
	end
      end
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


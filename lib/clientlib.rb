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

  def initialize(host="localhost", port=RDTNAPPIFPORT)
    @@log=RdtnLogger.instance()    
    @sendBuf = RdtnStringIO.new
    @bundleHandler = lambda {}
    @threads = Queue.new
    @pendingRequests = Hash.new()
    self.open(host, port)
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
      @threads.push(spawnThread(host, port, &connectBlock))
    end
  end

  def close
    until @threads.empty?
      @threads.pop.kill
    end
    @@log.debug("RdtnClient::close -- closing socket #{@s}")
    if socketOK?
      @s.close
    end
    EventDispatcher.instance().dispatch(:linkClosed, self)
  end

  def watch
    @threads.push(spawnThread { self.whenReadReady } )
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
	input=RdtnStringIO.new(data)
	processData(input)
      else
	@@log.debug("TCPLink::whenReadReady: no data read")
	# unregister socket and generate linkClosed event so that this
	# link can be removed

	self.close()              
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

    handlePendingRequests(typeCode, args)
    if typeCode == POST and /rdtn:bundles\/(\d+)\// =~ args[:uri] 
      @bundleHandler.call(args[:bundle])
    end
  end

  def checkError(typeCode, args)
    if typeCode == STATUS and args[:status] >= 400
      RdtnLogger.instance.error("An error occured for #{args[:uri]}: #{args[:message]}")
      return true
    end
    return false
  end

  def handlePendingRequests(typeCode, args)
    if @pendingRequests.has_key?(args[:uri])
      @pendingRequests[args[:uri]].call(typeCode, args)
      @pendingRequests.delete(args[:uri])
    end
  end

  def sendRequest(typeCode, args, &handler)
    handler = lambda {} if not handler
    @pendingRequests[args[:uri]] = handler
    sendPDU(typeCode, args)
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
    Thread.pass
  end

  def sendPDU(type, pdu)
    buf="" + type.chr() + Marshal.dump(pdu)
    send(buf)
  end

  def register(pattern, &handler)
    sendRequest(POST, {:uri => "rdtn:routetab/", :target => pattern})
    @bundleHandler = handler
  end

  def unregister(pattern)
    sendRequest(DELETE, {:uri => "rdtn:routetab/", :target => pattern})
  end

  def sendBundle(bundle)
    sendRequest(POST, {:uri => "rdtn:bundles/", :bundle => bundle})
  end

  def addRoute(pattern, link)
    sendRequest(POST, {:uri => "rdtn:routetab/", :target => pattern, 
	    				     :link => link})
  end

  def delRoute(pattern, linkName)
    sendRequest(DELETE, {:uri => "rdtn:routetab/", :target => pattern, 
	    				       :link => link})
  end

  def busy?
    return (not @pendingRequests.empty?)
  end

end


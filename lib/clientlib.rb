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

require "socket"
require "clientapi"
require "bundle"
require "queue"
require "rerun_thread"
require "queuedio"

class RdtnClient
  include RerunThread
  include QueuedSender
  include QueuedReceiver
  attr_reader :bundleHandler, :host, :port

  def initialize(host="localhost", port=RDTNAPPIFPORT, blocking=true)
    @host = host
    @port = port
    @bundleHandler = lambda {}
    @threads = Queue.new
    @pendingRequests = Hash.new()
    @subscriptions = []

    connectBlock = lambda do |h, p| 
      sock = TCPSocket.new(h, p) 
      queuedReceiverInit(sock)
      queuedSenderInit(sock)
      @threads.push(spawnThread { read })
    end
    if blocking
      connectBlock.call(host, port)
    else
      @threads.push(spawnThread(host, port, &connectBlock))
    end
  end

  def close(wait = nil)
    until @threads.empty?
      thr = @threads.pop
      res = thr.join(wait) if wait
      if not res
	thr.kill
	wait = nil
      end
    end
    rdebug(self, "RdtnClient::close -- closing socket #{@s}")
    @sendSocket.close if not @sendSocket.closed?
    @receiveSocket.close if not @receiveSocket.closed?
    EventDispatcher.instance().dispatch(:linkClosed, self)
  end

  def register(pattern, &handler)
    sendRequest(POST, {:uri => "rdtn:routetab/", :target => pattern})
    @bundleHandler = handler
    callBundleHandler = lambda do |args|
      bundle = args[:bundle]
      @bundleHandler.call(bundle)
    end
    @subscriptions.push([/rdtn:bundles\/([\w-]+)\//, callBundleHandler])
  end

  def unregister(pattern)
    sendRequest(DELETE, {:uri => "rdtn:routetab/", :target => pattern})
    @bundleHandler = lambda {}
  end

  def sendBundle(bundle)
    sendRequest(POST, {:uri => "rdtn:bundles/", :bundle => bundle})
  end
  
  def sendApplicationAcknowledgement(bundle)
    # generate reception SR
    bdsr = BundleStatusReport.new
    bdsr.reasonCode = BundleStatusReport::REASON_NO_ADDTL_INFO
    if (bundle.fragment?)
      bdsr.fragment = true
      bdsr.fragmentOffset = bundle.fragmentOffset
      bdsr.fragmentLength = bundle.aduLength
    end

    bdsr.ackedByApp = true
    bdsr.creationTimestamp = bundle.creationTimestamp
    bdsr.creationTimestampSeq = bundle.creationTimestampSeq
    bdsr.eidLength = bundle.srcEid.to_s.length
    bdsr.srcEid = bundle.srcEid.to_s

    b = Bundling::Bundle.new(bdsr.to_s)
    if (bundle.reportToEid.to_s != "dtn:none")
      b.destEid = bundle.reportToEid
    else
      b.destEid = bundle.srcEid
    end

    b.administrative = true
    b.lifetime = bundle.lifetime

    puts "SND: application acknowledgement status report to #{b.destEid}"
    
    sendBundle(b)
  end

  def addRoute(pattern, link)
    sendRequest(POST, {:uri => "rdtn:routetab/", :target => pattern, 
	    				     :link => link})
  end

  def delRoute(pattern, link)
    sendRequest(DELETE, {:uri => "rdtn:routetab/", :target => pattern, 
	    				       :link => link})
  end

  def busy?
    return (not @pendingRequests.empty?)
  end

  def subscribeEvent(eventId, &handler)
    uri = "rdtn:events/#{eventId.to_s}/"
    sendRequest(POST, {:uri => uri})
    callEventHandler = lambda do |args|
      argList = args[:args]
      handler.call(*argList)
    end
    @subscriptions.push([Regexp.new(uri), callEventHandler])
  end

  def getBundlesMatchingDest(dest, &handler)
    sendRequest(QUERY, {:uri => "rdtn:bundles/", :destEid => dest}) do |args|
      handler.call(args[:bundle])
    end
  end

  def deleteBundle(bundleId)
    sendRequest(DELETE, {:uri => "rdtn:bundles/#{bundleId}/"})
  end

  private
  def read
    begin
      doRead {|input| processData(input) }
    rescue SystemCallError    # lost TCP connection 
      rerror(self, "RDTNClient::read" + $!)
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

    handlePendingRequests(typeCode, args)
    if typeCode == POST 
      handlers = @subscriptions.find_all {|pattern, h|pattern === args[:uri]}
      handlers.each {|p, handler| handler.call(args)}
    end
  end

  def checkError(typeCode, args)
    if typeCode == STATUS and args[:status] >= 400
      rerror(self,
	"An error occured for #{args[:uri]}: #{args[:message]}")
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

  def send(data)
    sendQueueAppend(data)
    @threads << spawnThread { doSend }
    Thread.pass
  end

  def sendPDU(type, pdu)
    buf="" + type.chr() + Marshal.dump(pdu)
    send(buf)
  end

end


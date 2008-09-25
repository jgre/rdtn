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
require "bundle"
require "queue"
require "queuedio"

class RdtnClient
  include QueuedSender
  include QueuedReceiver
  attr_reader :bundleHandler, :host, :port

  def initialize(host="localhost", port=RDTNAPPIFPORT,evDis = nil,blocking=true)
    @host = host
    @port = port
    @evDis = evDis
    @bundleHandler = lambda {}
    @threads = Queue.new
    @pendingRequests = Hash.new()
    @subscriptions = []
    @lastTS = @lastSeqNo = 0

    connectBlock = lambda do |h, p| 
      sock = TCPSocket.new(h, p) 
      queuedReceiverInit(sock)
      queuedSenderInit(sock)
      @threads.push(Thread.new { read })
    end
    if blocking
      connectBlock.call(host, port)
    else
      @threads.push(Thread.new(host, port, &connectBlock))
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
    rdebug("RdtnClient::close -- closing socket #{@s}")
    @sendSocket.close if not @sendSocket.closed?
    @receiveSocket.close if not @receiveSocket.closed?
    @evDis.dispatch(:linkClosed, self) if @evDis
  end

  def register(pattern, &handler)
    sendRequest(:register, pattern) do |respType, bundles|
      case respType
      when :bundles
	bundles.each {|b| handler.call(b)}
	true
      when :error
	handleError(:register, pattern, bundles)
	false
      when :ok
	true
      end
    end
  end

  def unregister(pattern)
    sendRequest(:unregister, pattern)
  end

  def sendBundle(bundle)
    sendRequest(:sendBundle, bundle)
  end

  def sendDataTo(data, dest, senderTag = nil)
    sendRequest(:sendDataTo, data, dest, senderTag)
  end
  
  def sendApplicationAcknowledgement(bundle)
    sendRequest(:applicationAcknowledgement, bundle.bundleId)
  end

  def busy?
    return (not @pendingRequests.empty?)
  end

  def getBundlesMatchingDest(dest, &handler)
    sendRequest(:getBundlesMatchingDest, dest) do |respType, bundles|
      case respType
      when :bundles
	handler.call(bundles)
	true
      when :error
	handleError(:getBundlesMatchingDest, dest, bundles)
	false
      when :ok
	true
      end
    end
  end

  def deleteBundle(bundleId)
    sendRequest(:deleteBundle, bundleId)
  end

  private
  def read
    begin
      doRead {|input| processData(input) }
    rescue SystemCallError    # lost TCP connection 
      rerror("RDTNClient::read" + $!)
    end
    # If we are here, doRead hit an error or the link was closed.
    self.close()              
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
    if @pendingRequests.has_key?(msgId)
      again = @pendingRequests[msgId].call(type, *args[2..-1])
      @pendingRequests.delete(msgId) unless again
    end
  end

  def handleError(type, args, errorMessage)
    rerror("An error occured for #{type}: #{errorMessage}.")
  end

  def generateMessageId
    ts = Time.now.to_f
    if ts == @lastTS
      @lastSeqNo += 1
    else
      @lastTS    = ts
      @lastSeqNo = 0
    end
    @lastTS.to_s + @lastSeqNo.to_s
  end

  def sendRequest(type, *args, &handler)
    unless handler
      handler = lambda do |respType, *respArgs|
	handleError(type, args, respArgs) if respType == :error
	false
      end
    end
    msgId = generateMessageId
    @pendingRequests[msgId] = handler
    sendPDU(type, msgId, *args)
  end

  def sendBuf(data)
    sendQueueAppend(data)
    doSend
    #@threads << Thread.new { doSend }
    Thread.pass
  end

  def sendPDU(type, msgId, *pdu)
    sendBuf(Marshal.dump([type, msgId, *pdu]))
  end

end


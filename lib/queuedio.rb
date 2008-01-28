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
require "monitor"
require "rdtnerror"
require "queue"

# QueuedSender is a mixin module that manages a queue and sends its contents
# over a socket.
#
# When using this module, the variable +@sendSocket+ must be initialized to an
# open socket.
module QueuedSender

  def queuedSenderInit(sock)
    @sendQueue = RdtnStringIO.new
    @sendQueueChunkSize = 32768
    @sendSocket = sock
  end

  attr_writer :sendSocket, :sendQueueChunkSize

  def sendQueueAppend(data)
    @sendQueue.enqueue(data)
  end

  private
  # Send the queued data over the socket.
  #
  # This method workes through the queue until all its contents have been sent.
  # In most cases +doSend+ should be run in its onw thread.
  def doSend
    res = -1
    while @sendSocket and not @sendSocket.closed? and not @sendQueue.eof?
      buf = @sendQueue.read(@sendQueueChunkSize)
      begin
        res=@sendSocket.send(buf,0)
      rescue  RuntimeError => detail
        puts("socket send error " + detail)
      end
      
      if res < buf.length
	@sendQueue.pos -= (buf.length - res)
      end
    end
    return res
  end

end

# QueuedReceiver is a mixin module that manages a queue reading data from a
# socket.
#
# When using this module, the variable +@receiveSocket+ must be initialized to
# an open socket.
module QueuedReceiver

  def queuedReceiverInit(socket)
    @readQueue = RdtnStringIO.new
    @readQueueChunkSize = 32768
    @receiveSocket = socket
  end

  attr_writer :receiveSocket, :readQueueChunkSize

  # Read data from +@receiveSocket+ to +@readQueue+. Call a block for new data.
  #
  # This method loops until an error occurs. Should be run in a thread.
  # receiver.doRead {|queue| block } -> nil
  def doRead
    while true
      data = @receiveSocket.recv(@readQueueChunkSize)
      
      if data and data.length > 0
	@readQueue.enqueue(data)
	yield(@readQueue)
      else
	break
      end
    end
    return nil
  end
end

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

$:.unshift File.join(File.dirname(__FILE__), "..", "lib")

require 'queuedio'
require 'sdnv'
require 'socket'
require 'remcl'
require 'rerun_thread'
require 'fcntl'

module Rem

  class ProtocolError < RuntimeError
    def initialize(msg)
      super(msg)
    end
  end

  class NodeConnection

    attr_reader :id
    attr_accessor :connections

    #include QueuedSender
    include QueuedReceiver
    include RerunThread

    def initialize(sock)
      @sock = sock
      #@sock2 = sock.clone
      #@sock2.fcntl(Fcntl::F_SETFL, Fcntl::O_NONBLOCK)
      #sock.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
      queuedReceiverInit(sock)
      #queuedSenderInit(sock)
      @reader   = nil
      @dataSrc  = nil
      @dataDest = nil
      @dataSize = nil
      @connections = {}
      # Read initialial handshake
      hs = @sock.read(5)
      if hs.length != 5 or hs[0] != Rem::START
	raise ProtocolError, 'Invalid START command'
      end
      @id = hs[1..4].unpack('N')[0]
      @readerThread = spawnThread { read }
    end

    def connect(node2)
      @connections[node2.id] = node2
      buf = ''
      buf << Rem::CONNECT
      buf << [Time.now.to_f].pack('G')
      #buf << [Config.instance.time.to_f].pack('G')
      buf << [node2.id].pack('N')
      puts "Sending connect #{buf.length}"
      #@sock.fcntl(Fcntl::F_SETFL, Fcntl::O_NONBLOCK)
      ret = @sock.send(buf, 0)
      #@sock.fcntl(Fcntl::F_SETFL, 0)
      puts "Sent disconnect #{ret}, #{buf.length}"
      #puts "Sent Connect #{ret}, #{buf.length}"
      #sendQueueAppend(buf)
      #doSend
    end

    def disconnect(node2)
      @connections[node2.id] = nil
      buf = ''
      buf << Rem::DISCONNECT
      buf << [Time.now.to_f].pack('G')
      #buf << [Config.instance.time.to_f].pack('G')
      buf << [node2.id].pack('N')
      puts "Sending disconnect #{buf.length}"
      #@sock.fcntl(Fcntl::F_SETFL, Fcntl::O_NONBLOCK)
      ret = @sock.send(buf, 0)
      puts "Sent disconnect #{ret}, #{buf.length}"
      #sendQueueAppend(buf)
      #doSend
      #spawnThread { doSend }
    end

    def shutdown
      @readerThread.kill if @readerThread
      #buf = ''
      #buf << Rem::SHUTDOWN
      #buf << [Config.instance.time.to_f].pack('G')
      #sendQueueAppend(buf)
      #doSend
    end

    def sendData(src, data)
      buf = ''
      buf << Rem::SENDDATA
      buf << [Time.now.to_f].pack('G')
      #buf << [Config.instance.time.to_f].pack('G')
      buf << [@id].pack('N')
      buf << [src].pack('N')
      buf << Sdnv.encode(data.length)
      buf << data
      @sock.send(buf, 0)
      #sendQueueAppend(buf)
      #doSend
      #spawnThread { doSend }
    end

    private

    def read
      #doRead do |input|
      input = @sock
      loop do
	unless @reader
	  #puts "Core: reading..."
	  typeCode = input.read(1)[0] #getc
	  #puts "Core: read #{typeCode}"
	  case typeCode
	  when Rem::SENDDATA then @reader = :readData
	  end
	  timestamp = input.read(8).unpack('G')[0]
	  lag = Time.now.to_f - timestamp
	  #lag = Config.instance.time.to_f - timestamp
	  #puts "----------LAG (core): #{lag} #{@reader} #{timestamp}" #if lag > 2
	end
	self.send(@reader, input, lag) if @reader
      end
    end

    def readData(input, lag)
      @dataDest = input.read(4).unpack('N')[0] unless @dataDest
      @dataSrc  = input.read(4).unpack('N')[0] unless @dataSrc
      @dataSize = Sdnv.decode(input.read(2))[0]        unless @dataSize
      buf = input.read(@dataSize)
      #open("dbg.in#{@dataDest}-#{@dataSrc}", 'w') do |f|
      #  f.write(buf)
      #end
      if buf.length == @dataSize
	#puts "(Core) Data from #{@dataSrc} to #{@dataDest} (Size: #{@dataSize}, Lag: #{lag})"
	if @connections[@dataDest]
	  @connections[@dataDest].sendData(@dataSrc, buf)
	  #puts "Sending OK"
	else
	  #puts "No Connection! #{@id}, #{@dataDest}"
	end
	@dataSize -= buf.length
      end
      if @dataSize <= 0
	# Reset reader state
	@dataDest = @dataSrc = @dataSize = @reader = nil
      end
    end

  end

end # module

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
require 'cl'
require 'remconf'

module Rem

  START      = 1
  CONNECT    = 2
  DISCONNECT = 3
  SENDDATA   = 4
  SHUTDOWN   = 5

  class RemLink < Link

    attr_accessor :remoteEid

    def initialize(dest, iface)
      super()
      @dest = dest
      @iface = iface
      @remoteEid = "dtn://kasuari#{dest}/"
      EventDispatcher.instance.dispatch(:linkOpen, self)
    end

    def sendBundle(bundle)
      @iface.sendBundle(@dest, bundle.to_s)
    end

  end

  class RemInterface < Interface

    #include QueuedSender
    include QueuedReceiver

    def initialize(name, options)
      @name = name
      @links = {}
      @reader = nil

      @host     = 'localhost'
      @port     = Rem::REM_PORT
      timeAddr = '224.224.224.2'
      timePort = 12346
      if options.has_key?(:host)
	@host = options[:host]
      end
      if options.has_key?(:port)
	@port = options[:port]
      end
      if options.has_key?(:timeAddr)
	timeAddr = options[:timeAddr]
      end
      if options.has_key?(:timePort)
	timePort = options[:timePort]
      end
      if /kasuari([0-9]+)/ =~ RdtnConfig::Settings.instance.localEid
	@id = $1.to_i
      else
	puts "Error: Could not parse id from EID #{RdtnConfig::Settings.instance.localEid}"
	exit(0)
      end

      @sock = TCPSocket.new(@host, @port)
      queuedReceiverInit(@sock)
      #queuedSenderInit(@sock)

      # Initial START message
      buf = ''
      buf << Rem::START
      buf << [@id].pack('N')
      @sock.send(buf, 0)

      puts "RemCL sending START"
      spawnThread { watch }
      TimeTickReceiver.new(timeAddr, timePort) unless options[:realtime]
    end

    def sendBundle(dest, data)
      buf = ''
      buf << Rem::SENDDATA
      buf << [RdtnTime.now.to_f].pack('G')
      buf << [dest].pack('N')
      buf << [@id].pack('N')
      buf << Sdnv.encode(data.length)
      buf << data
      @sock.send(buf, 0)
      #open("dbg.out-#{dest}-#{@id}", 'w') do |f|
      #  f.write(buf)
      #end
      #sendQueueAppend(buf)
      #spawnThread { doSend }
    end

    private

    def watch
      #doRead do |input|
      input = @sock
      loop do
	unless @reader
	  #puts "Client #{@id}: reading"
	  typeCode = input.read(1)[0] #getc
	  #puts "Client #{@id}: read #{typeCode}"
	  case typeCode
	  when Rem::SENDDATA   then @reader = :readData
	  when Rem::CONNECT    then @reader = :connect
	  when Rem::DISCONNECT then @reader = :disconnect
	  when Rem::SHUTDOWN   then @reader = :shutdown
	  end
	  timestamp = input.read(8).unpack('G')[0]
	  lag = RdtnTime.now.to_f - timestamp
	  #puts "----------LAG (client): #{lag} #{@reader} #{timestamp}" #if lag > 2
	end
	self.send(@reader, input, lag) if @reader
      end
    end

    def readData(input, lag)
      @dataDest = input.read(4).unpack('N')[0] unless @dataDest
      @dataSrc  = input.read(4).unpack('N')[0] unless @dataSrc
      @dataSize = Sdnv.decode(input.read(2))[0]        unless @dataSize
      #reset = (@dataSize <= (input.length - input.pos))
      buf = input.read(@dataSize)
      #open("dbg.cl#{@dataDest}-#{@dataSrc}", 'w') do |f|
      #  f.write(buf)
      #end
      if buf.length == @dataSize
	#puts "(Node #{@id}) Data from #{@dataSrc} to #{@dataDest} (Size: #{@dataSize}, Lag #{lag})"
	sio = StringIO.new(buf)
	if @links[@dataSrc]
	  #puts "(Node #{@id}) REMCL Receiving OK #{buf.length}"
	  EventDispatcher.instance().dispatch(:bundleData, sio, @links[@dataSrc])
	else
	  puts 'REMCL No Connection!'
	end
	@dataSize -= buf.length
      end
      if @dataSize <= 0
	# Reset reader state
	@dataDest = @dataSrc = @dataSize = @reader = nil
      end
      #if reset

      #  open("dbg.cl#{@dataDest}-#{@dataSrc}", 'w') do |f|
      #    f.write(buf)
      #  end
      #  # Reset reader state
      #  @dataDest = @dataSrc = @dataSize = @reader = nil
      #end
    end

    def connect(input, lag)
      nodeId =  input.read(4).unpack('N')[0]
      puts "(Node #{@id}) REMCL Connect #{@id}, #{nodeId}, #{RdtnTime.now.to_f}, Lag: #{lag}"
      @links[nodeId] = RemLink.new(nodeId, self)
      @reader = nil
    end

    def disconnect(input, lag)
      nodeId =  input.read(4).unpack('N')[0]
      puts "(Node #{@id}) REMCL Disconnect #{@id}, #{nodeId}, #{RdtnTime.now.to_f}, Lag: #{lag}"
      @links[nodeId].close
      @links[nodeId] = nil
      @reader = nil
    end

    def shutdown(input)
      puts "RemCL Shutdown"
      exit(0)
      @reader = nil
    end

  end

  class TimeTickReceiver

    include QueuedReceiver
    include RerunThread

    def initialize(timeAddr, timePort)
      # Set the global Rdtn clock to use the time we receive vom the emulation
      # core
      @timer = Time.now
      RdtnTime.timerFunc = lambda {@timer}

      sock = UDPSocket.new
      queuedReceiverInit(sock)

      ip =  IPAddr.new(timeAddr).hton + IPAddr.new("0.0.0.0").hton

      begin
	sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
	sock.bind(Socket::INADDR_ANY, timePort)
	sock.setsockopt(Socket::IPPROTO_IP, Socket::IP_MULTICAST_LOOP, 1)
	sock.setsockopt(Socket::IPPROTO_IP, Socket::IP_ADD_MEMBERSHIP, ip)
      rescue RuntimeError => detail
	puts("socket system call error: " + detail)
      end

      listenerThread = spawnThread { readTimerTicks }
    end

    def readTimerTicks
      doRead do |input| 
	dat = input.read(8)
	@timer = Time.at(dat.unpack('G')[0])
      end
    end

  end

end # module

regCL(:rem, Rem::RemInterface, Rem::RemLink)

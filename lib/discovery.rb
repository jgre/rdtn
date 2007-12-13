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

require 'cl'
require 'bundle'
require 'configuration'
require 'rerun_thread'
require 'genparser'
require 'ipaddr'
require 'platform.rb'

class Announcement

  include GenParser

  attr_accessor :clType, :interval, :inetAddr, :inetPort, :senderEid, :lastSeen

  def Announcement.typeSymToId(typeSym)
    case typeSym
    when :tcp then 1
    when :udp then 2
    else 0
    end
  end

  def Announcement.typeIdToSym(typeId)
    case typeId
    when 1 then :tcp
    when 2 then :udp
    else :undefined
    end
  end

  def initialize(clType = nil, interval = 1, addr = "127.0.0.1", port = 12345, 
		 eid = RdtnConfig::Settings.instance.localEid)
    @clType    = Announcement.typeSymToId(clType)
    @interval  = interval
    @inetAddr  = IPSocket.getaddress(addr)
    @inetPort  = port
    @senderEid = eid.to_s
    @lastSeen  = RdtnTime.now

    defField(:type, :length => 1, :decode => GenParser::NumDecoder,
	     :handler => :clType=)
    defField(:interval, :length => 1, :decode => GenParser::NumDecoder,
	     :handler => :interval=)
    defField(:packetLen, :length => 2, :decode => GenParser::NumDecoder)
    defField(:addr, :length => 4, :decode => InetAddrDecoder, 
	     :handler => :inetAddr=)
    defField(:port, :length => 2, :decode => GenParser::NumDecoder,
	     :handler => :inetPort=)
    defField(:eidLength, :length => 2, :decode => GenParser::NumDecoder,
	     :block => lambda {|len| defField(:senderEid, :length => len)})
    defField(:senderEid, :handler => :senderEid=)
  end

  def ==(ann)
    return (@clType == ann.clType and @inetAddr == ann.inetAddr and 
	    @inetPort == ann.inetPort and @senderEid == ann.senderEid)
  end

  def seenNow
    @lastSeen = RdtnTime.now
  end

  def typeSym
    Announcement.typeIdToSym(@clType)
  end

  def to_s
    data = ""
    data << @clType
    data << @interval
    data << [12 + @senderEid.to_s.length].pack('n') # 12 is the total size of  
    						    # the fixed length fields
    data << IPAddr.new(@inetAddr).hton
    data << [@inetPort].pack('n')
    data << [@senderEid.to_s.length].pack('n')
    data << @senderEid.to_s
    return data
  end

  def Announcement.decodeInetAddr(sio, length)
    if length != 4
      raise TypeError, "Cannot decode Inet Addr with length #{length}"
    end
    data = sio.read(length)
    if not data or data.length < length
      raise InputTooShort, length
    end
    return IPAddr.new_ntoh(data).to_s
  end

  InetAddrDecoder = Announcement.method(:decodeInetAddr)

end

class IPDiscovery < Monitor

  include QueuedReceiver
  include RerunThread

  def initialize(address, port, interval = 10, announceIfs = [])
    super()
    @addr        = address
    @port        = port
    @interval    = interval
    @announceIfs = announceIfs
    @recvdAnns   = []
    @myAnns      = @announceIfs.map do |aif| 
      Announcement.new(CLReg.instance.getName(aif.class), @interval, aif.host,
		       aif.port)
    end
    @aliveTimer  = interval * 2
    housekeeping
    EventDispatcher.instance().subscribe(:linkClosed) do |link|
      @recvdAnns.delete_if do |ann| 
        #puts "Discovery #{ann.inetAddr == link.host and ann.inetPort == link.port}"
        ann.inetAddr == link.host and ann.inetPort == link.port
      end
    end
  end

  def start
    @sock = UDPSocket.new
    ip =  IPAddr.new(@addr).hton + IPAddr.new("0.0.0.0").hton


    begin
      @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
      @sock.bind(Socket::INADDR_ANY, @port)
      @sock.setsockopt(Socket::IPPROTO_IP, Socket::IP_MULTICAST_LOOP, 1)
      @sock.setsockopt(Socket::IPPROTO_IP, Socket::IP_ADD_MEMBERSHIP, ip)
    rescue RuntimeError => detail
      #puts("socket system call error: " + detail)
    end

    queuedReceiverInit(@sock)
    @listenerThread = spawnThread { read }
    @senderThread   = spawnThread { announce }
  end

  def close
    if defined? @listenerThread and @listenerThread
      @listenerThread.kill
    end
    if defined? @senderThread and @senderThread
      @senderThread.kill
    end
    if not @receiveSocket.closed?
      @receiveSocket.close
    end
  end

  private
  def read
    begin
      doRead do |input|
	until input.eof?
	  ann = Announcement.new
	  ann.parse(input)
	  
	  if @myAnns.include?(ann) or @recvdAnns.include?(ann)
	    dup = @recvdAnns.find {|a| a == ann}
	    dup.seenNow if dup
	    next
	  end

	  @aliveTimer = [@aliveTimer, ann.interval * 2].min
	  @recvdAnns.push(ann)
	  if ann.typeSym == :tcp or ann.typeSym == :udp
	    opts = {:host => ann.inetAddr, :port => ann.inetPort }
	    EventDispatcher.instance.dispatch(:opportunityAvailable, 
					      ann.typeSym, opts, ann.senderEid)
	  end
	end
      end
    rescue SystemCallError
      rerror(self, "IPDiscovery::read" + $!)
    rescue ProtocolError => err
      rwarn(self, "IPDiscovery: #{err}")
    end
    # If we are here, doRead hit an error or the link was closed.
    self.close
  end

  def announce
    return nil if @myAnns.empty?
    encodedAnns = @myAnns.map {|ann| ann.to_s}
    while true
      data = encodedAnns.join
      ret = @sock.send(data, 0, @addr, @port)
      sleep(@interval)
    end
  end

  def housekeeping
    Thread.new do 
      while true
	sleep(@aliveTimer)
	delIndex = []
	@recvdAnns.each_with_index do |ann, i|
	  if ann.lastSeen < (RdtnTime.now - ann.interval*2)
	    opts = {:host => ann.inetAddr, :port => ann.inetPort }
	    EventDispatcher.instance.dispatch(:opportunityDown, 
					      ann.typeSym, opts, ann.senderEid)
	    rdebug(self, "Announcement timed out for #{ann.senderEid}")
	    delIndex.push(i)
	  end
	end
	synchronize {delIndex.each {|i| @recvdAnns.delete_at(i)} }
      end
    end
  end

end

class KasuariDiscovery < IPDiscovery

  def initialize(naddrs, port, interval = 10, announceIfs = [])
    super(IPSocket.getaddress(Socket.gethostname), port, interval, announceIfs)
    @baseAddr = "10.0.0."
    @naddrs = naddrs
  end

  def start
    @sock = UDPSocket.new
    @sock.bind(Socket::INADDR_ANY, @port)
    queuedReceiverInit(@sock)
    @listenerThread = spawnThread { read }
    @senderThread   = spawnThread { announce }
  end

  def announce
    return nil if @myAnns.empty?
    encodedAnns = @myAnns.map {|ann| ann.to_s}
    while true
      data = encodedAnns.join
      1.upto(@naddrs) do |i| 
        ret = @sock.send(data, 0, @baseAddr + i.to_s, @port)
      end
      sleep(@interval)
    end
  end

end

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

class Announcement

  include GenParser

  attr_accessor :clType, :interval, :inetAddr, :inetPort, :senderEid

  def Announcement.typeSymToId(typeSym)
    case typeSym
    when :tcp: 1
    when :udp: 2
    else 0
    end
  end

  def Announcement.typeIdToSym(typeId)
    case typeId
    when 1: :tcp
    when 2: :udp
    else :undefined
    end
  end

  def initialize(clType = nil, interval = 1, addr = "localhost", port = 12345, 
		 eid = RdtnConfig::Settings.instance.localEid)
    @clType    = Announcement.typeSymToId(clType)
    @interval  = interval
    @inetAddr  = addr
    @inetPort  = port
    @senderEid = eid

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

  def typeSym
    Announcement.typeIdToSym(@clType)
  end

  def to_s
    data = ""
    data << @clType
    data << @interval
    data << [12 + @senderEid.to_s.length].pack('n') # 12 is the total size of  
    						    # the fixed length fields
    data << IPAddr.new(IPSocket.getaddress(@inetAddr)).hton
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

class IPDiscovery

  include QueuedReceiver
  include RerunThread

  def initialize(address, port, interval = 10, announceIfs = [])
    @log         = RdtnConfig::Settings.instance.getLogger(self.class.name)
    @addr        = address
    @port        = port
    @interval    = interval
    @announceIfs = announceIfs
  end

  def start(sendOnly = false)
    @sock = UDPSocket.new
    unless sendOnly
      ip =  IPAddr.new(@addr).hton + IPAddr.new("0.0.0.0").hton
      @sock.setsockopt(Socket::IPPROTO_IP, Socket::IP_ADD_MEMBERSHIP, ip)
      #@sock.setsockopt(Socket::IPPROTO_IP, Socket::IP_MULTICAST_LOOP, 0)
      @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
      @sock.bind(Socket::INADDR_ANY, @port)
      queuedReceiverInit(@sock)
      @listenerThread = spawnThread { read }
    end
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
	  if ann.typeSym == :tcp or ann.typeSym == :udp
	    opts = {:host => ann.inetAddr, :port => ann.inetPort }
	    EventDispatcher.instance.dispatch(:opportunityAvailable, 
					      ann.typeSym, opts, ann.senderEid)
	  end
	end
      end
    rescue SystemCallError
      @log.error("IPDiscovery::read" + $!)
    rescue ProtocolError => err
      @log.warn("IPDiscovery: #{err}")
    end
    # If we are here, doRead hit an error or the link was closed.
    self.close
  end

  def announce
    announcements = @announceIfs.map do |aif| 
      Announcement.new(CLReg.instance.getName(aif.class), @interval, aif.host,
					      aif.port)
    end
    return nil if announcements.empty?
    while true
      encodedAnns = announcements.map {|ann| ann.to_s}
      data = encodedAnns.join
      ret = @sock.send(data, 0, @addr, @port)
      sleep(@interval)
    end
  end

end

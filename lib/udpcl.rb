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
# $Id$

# TCP convergence layer

require "socket"
require "event-loop"

require "rdtnlog"
require "rdtnerror"
require "configuration"
require "cl"
require "sdnv"
require "queue"
require "rdtnevent"
require "eidscheme"
require "stringio"
require "genparser"

MAX_UDP_PACKET = 65535
UDPCLPORT = 4557

module UDPCL

  class UDPLink < Link
    attr_accessor :remoteEid, :maxBundleSize

    def initialize(socket = 0)
      super()
      @s = socket
    end

    def open(name, options)
      self.name = name
      port = UDPCLPORT 
      host = nil 

      if options.has_key?(:host)
	host = options[:host]
      end
      if options.has_key?(:port)
	port = options[:port]
      end
      if options.has_key?(:maxBundleSize)
	@maxBundleSize = options[:maxBundleSize]
      end

      if(socketOK?())
	close
      end
      @s = UDPSocket.new
      @s.connect(host, port)
    end

    def close
      RdtnLogger.instance.debug("UDPLink::close")
      if socketOK?
	@s.close
      end
    end

    def socketOK?
      (@s.class.to_s=="UDPSocket") && !@s.closed?()
    end
      
    def sendBundle(bundle)
      res=-1
      if(socketOK?())
	res=@s.send(bundle.to_s, 0)
      end
      return res
    end

  end

  class UDPInterface < Interface

    def initialize(name, options)
      self.name = name
      host = nil
      port = UDPCLPORT

      if options.has_key?(:host)
	host = options[:host]
      end
      if options.has_key?(:port)
	port = options[:port]
      end

      RdtnLogger.instance.debug("Building UDP interface with port=#{port} and hostname=#{host}")
      @s = UDPSocket.new
      @s.bind(host, port)
      @s.will_block = false
      @s.on_readable {self.whenAccept }
      @s.monitor_event(:readable)
    end
    
    def whenAccept()
      RdtnLogger.instance.debug("UDPInterface::whenAccept")

      begin
        data = @s.recvfrom(MAX_UDP_PACKET)
      rescue SystemCallError
        @@log.error("UDPLink::whenReadReady::recvfrom" + $!)
      end
      if defined? data && (data[0].length()>0)
	sio = StringIO.new(data[0])
	EventDispatcher.instance().dispatch(:bundleData, sio, true, self)
      end

    end
    
    def close
      if not @s.closed?
        @s.close
      end
    end
    
  end

end #module UDPCL

regCL(:udp, UDPCL::UDPInterface, UDPCL::UDPLink)

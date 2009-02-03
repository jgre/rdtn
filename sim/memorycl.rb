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
require 'cl'
require 'eventqueue'

module Sim

  class MemoryLink < Link

    attr_accessor :remoteEid
    attr_reader   :nodeId, :bytesPerSec

    def initialize(config, evDis, nodeId = nil, dest = nil, peerLink = nil,
		   bytesPerSec = 1024, sim = nil)
      super(config, evDis)
      @nodeId      = nodeId
      @dest        = dest
      @remoteEid   = "dtn://kasuari#{@dest}/" if dest
      @peerLink    = peerLink
      @bytesPerSec = bytesPerSec
      @sim         = sim
      @bytesToSend = 0
      @queuedBundle = nil
      @evDis.dispatch(:linkOpen, self) if @peerLink
    end

    def open(name, options)
      @name        = name if name
      @nodeId      = options[:nodeId]
      @memIf       = options[:memIf]
      @sim         = options[:sim]
      @dest        = @memIf.nodeId
      @peerLink    = @memIf.acceptConnection(self)
      @remoteEid   = "dtn://kasuari#{@dest}/"
      @bytesPerSec = options[:bytesPerSec]
      @evDis.dispatch(:linkOpen, self) if @peerLink
    end

    def close
      super
      pl           = @peerLink
      @peerLink    = nil
      pl.close if pl

      if @queuedBundle
	bytesTransmitted = (RdtnTime.now - @queuedSince).to_i * @bytesPerSec
	@sim.log(:transmissionError, @nodeId, @dest, :transmitted => bytesTransmitted, :bundle => @queuedBundle)
      end
      @queuedBundle = nil
      @queuedSince  = nil
    end

    def busy?
      @queuedBundle
    end

    def sendBundle(bundle)
      @queuedBundle = bundle
      @queuedSince  = RdtnTime.now
      @sim.after(bundle.payload.bytesize / @bytesPerSec.to_f) do
        if @peerLink
	  @queuedBundle = nil

          @evDis.dispatch(:bundleForwarded, bundle, self)
          @sim.log(:bundleForwarded, @nodeId, @dest, :bundle => bundle)

          @peerLink.receiveBundle(bundle, self)
        else
          @evDis.dispatch(:transmissionError, bundle, self)
        end
        false
      end
    end

    def receiveBundle(bundle, link)
      @peerLink = link unless @peerLink
      @evDis.dispatch(:bundleParsed, bundle.wireCopy(self))
    end

  end

  class MemoryInterface < Interface

    attr_reader :nodeId
    attr_accessor :bytesPerSec

    def initialize(config, evDis, name, options)
      @config      = config
      @evDis       = evDis
      @sim         = options[:sim]
      @nodeId      = options[:nodeId]
      @bytesPerSec = options[:bytesPerSec]
      @node        = options[:node]
    end

    def acceptConnection(peerLink)
      link = MemoryLink.new(@config, @evDis, @nodeId, peerLink.nodeId, peerLink,
			    @bytesPerSec, @sim)
      @node.links[peerLink.nodeId] = link
      link
    end

  end

end # module

regCL(:memory, Sim::MemoryInterface, Sim::MemoryLink)

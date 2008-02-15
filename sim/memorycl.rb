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
    attr_reader   :nodeId

    def initialize(config, evDis, nodeId = nil, dest = nil, peerLink = nil,
		   bytesPerSec = 1024)
      super(config, evDis)
      @nodeId      = nodeId
      @dest        = dest
      @remoteEid   = "dtn://kasuari#{@dest}/" if dest
      @peerLink    = peerLink
      @bytesPerSec = bytesPerSec
      @bytesToSend = 0
      @queue       = []
      @evDis.dispatch(:linkOpen, self) if @peerLink
    end

    def open(name, options)
      @name        = name if name
      @nodeId      = options[:nodeId]
      @memIf       = options[:memIf]
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
      @bytesToSend = 0
      @queue       = []
    end

    def sendBundle(bundle)
      if @peerLink
	@queue.push(bundle)
      else
	raise RuntimeError, "(Node#{@nodeId}) Broken MemoryLink to #{@dest}, #{self}"
      end
    end

    def process(nSec)
      #puts "process bps #{@bytesPerSec}"
      @bytesToSend += nSec * @bytesPerSec
      until @queue.empty?
	break if @queue[0].payload.length > @bytesToSend
	if @peerLink
	  bundle = @queue.shift
	  @evDis.dispatch(:bundleForwarded, bundle, self)
	  @peerLink.receiveBundle(bundle, self)
	  @bytesToSend -= bundle.payload.length
	else
	  raise RuntimeError, "(Node#{@nodeId}) Broken MemoryLink to #{@dest}, #{self}"
	end
      end
      # We can only "save" send contingent if there is something to transmitt
      # right now
      @bytesToSend = 0 if @queue.empty?
    end

    def receiveBundle(bundle, link)
      @peerLink = link unless @peerLink
      sio = StringIO.new(bundle.to_s)
      @evDis.dispatch(:bundleData, sio, self)
    end

  end

  class MemoryInterface < Interface

    attr_reader :nodeId

    def initialize(config, evDis, name, options)
      @config      = config
      @evDis       = evDis
      @nodeId      = options[:nodeId]
      @bytesPerSec = options[:bytesPerSec]
      @node        = options[:node]
    end

    def acceptConnection(peerLink)
      link = MemoryLink.new(@config, @evDis, @nodeId, peerLink.nodeId, peerLink,
			    @bytesPerSec)
      @node.links[peerLink.nodeId] = link
      link
    end

  end

end # module

regCL(:memory, Sim::MemoryInterface, Sim::MemoryLink)

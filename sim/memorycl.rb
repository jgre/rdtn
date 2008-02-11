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
require 'conf'
require 'eventqueue'

module Sim

  class MemoryLink < Link

    attr_accessor :remoteEid

    def initialize(nodeId, evDis, dest, bytesPerSec)
      super(evDis)
      @nodeId = nodeId
      @dest   = dest
      @remoteEid = "dtn://kasuari#{@dest}/"
      @bytesPerSec = bytesPerSec
      @bytesToSend = 0
      @queue = []
    end

    def close
      #puts "(Node#{@nodeId}) Closing link to #{@dest}. Deleting #{@queue.length} queued bundles." unless @queue.empty?
      super
      @peerLink = nil
      @bytesToSend = 0
      @queue = []
    end

    def peerLink=(memLink)
      @peerLink = memLink
      #Profiler__::start_profile
      @evDis.dispatch(:linkOpen, self)
      #Profiler__::stop_profile
    end

    def sendBundle(bundle)
      if @peerLink
	@queue.push(bundle)
      else
	raise RuntimeError, "(Node#{@nodeId}) Broken MemoryLink to #{@dest}, #{self}"
      end
    end

    def process(nSec)
      @bytesToSend += nSec * @bytesPerSec
      #puts "(Node#{@nodeId}) Can send #{@bytesToSend} bytes"
      until @queue.empty?
	break if @queue[0].payload.length > @bytesToSend
	if @peerLink
	  bundle = @queue.shift
	  @evDis.dispatch(:bundleForwarded, bundle, self)
	  @peerLink.receiveBundle(bundle, self)
	  #puts "(Node#{@nodeId}) Sent #{bundle.payload.length} bytes"
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
      self.peerLink = link unless @peerLink
      bundle.incomingLink = self
      @evDis.dispatch(:bundleParsed, bundle)
    end

  end

  class MemoryInterface < Interface
  end

end # module

regCL(:memory, Sim::MemoryInterface, Sim::MemoryLink)

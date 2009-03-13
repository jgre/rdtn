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
require 'memorycl'
require 'bundle'
require 'bundleworkflow'
require 'daemon'

module Sim

  class Node < RdtnDaemon::Daemon

    attr_reader   :id, :links, :memIf
    attr_accessor :bytesPerSec
    alias linkCapacity= bytesPerSec=
    #attr_accessor :connections

    def initialize(id, sim)
      @id          = id
      @sim         = sim
      super("dtn://kasuari#{@id}/")
      @nbundles    = 0
      @bytesPerSec = 1024

      @memIf = addIf(:memory, "mem0", :nodeId=>@id, :bytesPerSec=>bytesPerSec,
                     :node=>self, :sim=>@sim)

      @evDis.subscribe(:bundleStored) do |bundle|
	@sim.log(:bundleStored, @id, nil, :bundle => bundle)
      end
      @evDis.subscribe(:bundleRemoved) do |bundle|
	@sim.log(:bundleRemoved, @id, nil, :bundle => bundle)
      end
    end

    def process(nSec)
      @links.each_value {|link| link.process(nSec) if link}
    end

    def connect(node2)
      addLink(:memory, "simlink#{node2.id}", :nodeId=>@id,
	      :memIf=>node2.memIf, :bytesPerSec=>@bytesPerSec,
	      :sim=>@sim)
    end

    def disconnect(node2)
      removeLink("simlink#{node2.id}")
    end

    def sendBundle(bundle)
      bundle.srcEid = makeLocalEid(bundle.srcEid)
      @sim.log(:bundleCreated, @id, nil, :bundle => bundle)
      super
    end

    def register(eid = nil, &handler)
      super
      @sim.log(:registered, @id, nil, :eid => eid)
    end

    def unregister(eid)
      super
      @sim.log(:unregistered, @id, nil, :eid => eid)
    end

  end

end # module

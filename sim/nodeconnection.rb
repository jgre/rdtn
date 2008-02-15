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
require 'stats'
require 'daemon'

module Sim

  class Node < RdtnDaemon::Daemon

    attr_reader   :id, :links, :memIf
    #attr_accessor :connections

    def initialize(dirName, id, bytesPerSec=1024, configPath=nil, channels=[])
      @id    = id
      super("dtn://kasuari#{@id}/")
      @nbundles = 0
      @bytesPerSec = bytesPerSec

      @config.store = Storage.new(@evDis)
      # Create logging environment for the node
      subDirName = File.join(dirName, "kasuari#{@id}")
      Dir.mkdir(subDirName) unless File.exist?(subDirName)
      @config.setStatDir(subDirName)
      parseConfigFile if configPath
      if channels
	channels.each {|chan| register(chan) {}}
      end
      @memIf = addIf(:memory, "mem0", :nodeId=>@id, :bytesPerSec=>bytesPerSec,
		    :node=>self)
    end

    #def self.connect(node1, node2)
    #  node1.addConnection(node2)
    #  node2.addConnection(node1)
    #  node1.startConnection(node2)
    #  node2.startConnection(node1)
    #end

    #def self.disconnect(node1, node2)
    #  node1.closeConnection(node2)
    #  node2.closeConnection(node1)
    #end

    def process(nSec)
      @links.each_value {|link| link.process(nSec) if link}
    end

    def connect(node2)
      rdebug(self, "Connecting #{@id} -> #{node2.id}")
      addLink(:memory, "simlink#{node2.id}", :nodeId=>@id,
	      :memIf=>node2.memIf, :bytesPerSec=>@bytesPerSec)
    end

    def disconnect(node2)
      removeLink("simlink#{node2.id}")
    end

    #def addConnection(node2)
    #  @links[node2.id] = MemoryLink.new(@id, @evDis, node2.id, 
    #    				@config.bytesPerSec)
    #end

    #def startConnection(node2)
    #  if node2.links[@id]
    #    @links[node2.id].peerLink = node2.links[@id]
    #  else
    #    raise RuntimeError, "(Core) Node#{@id} cannot start connection to node{node2.id}"
    #  end
    #end

    #def closeConnection(node2)
    #  @links[node2.id].close if @links[node2.id]
    #  @links[node2.id] = nil
    #end

    def createBundle(channel)
      payload = "a" * @config.bundleSize
      sendDataTo(payload, channel)
    end

  end

end # module

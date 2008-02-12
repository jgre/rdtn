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

module Sim

  class Node

    attr_reader   :id, :links
    #attr_accessor :connections

    def initialize(config, id, channels = [])
      @config = config
      @links = {}
      @id    = id
      @nbundles = 0

      # Create logging environment for the node
      subDirName = File.join(@config.dirName, "kasuari#{@id}")
      Dir.mkdir(subDirName) unless File.exist?(subDirName)
      # Start minimal RDTN instance for the node
      @evDis = EventDispatcher.new
      stats = Stats::StatGrabber.new(@evDis,
        			     File.join(subDirName, "time.stat"),
        			     File.join(subDirName, "out.stat"),  
        			     File.join(subDirName, "in.stat"),
        			     File.join(subDirName, "contact.stat"),
        			     File.join(subDirName, "subscribe.stat"),
        			     File.join(subDirName, "store.stat"))
      @rdtnConfig = RdtnConfig::Settings.new(@evDis)
      @rdtnConfig.localEid = "dtn://kasuari#{@id}/"
      Bundling::BundleWorkflow.registerEvents(@rdtnConfig, @evDis)
      RdtnConfig::Reader.load(@evDis, @config.configPath, @rdtnConfig)
      if channels
	channels.each {|chan| @rdtnConfig.subscriptionHandler.subscribe(chan)}
      end
    end

    def self.connect(node1, node2)
      node1.addConnection(node2)
      node2.addConnection(node1)
      node1.startConnection(node2)
      node2.startConnection(node1)
    end

    def self.disconnect(node1, node2)
      node1.closeConnection(node2)
      node2.closeConnection(node1)
    end

    def process(nSec)
      @links.each_value {|link| link.process(nSec) if link}
    end

    def addConnection(node2)
      @links[node2.id] = MemoryLink.new(@id, @evDis, node2.id, 
					@config.bytesPerSec)
    end

    def startConnection(node2)
      if node2.links[@id]
	@links[node2.id].peerLink = node2.links[@id]
      else
	raise RuntimeError, "(Core) Node#{@id} cannot start connection to node{node2.id}"
      end
    end

    def closeConnection(node2)
      @links[node2.id].close if @links[node2.id]
      @links[node2.id] = nil
    end

    def createBundle(channel)
      payload = "a" * @config.bundleSize
      b = Bundling::Bundle.new(payload, EID.new(channel), @rdtnConfig.localEid)
      @evDis.dispatch(:bundleParsed, b)
      @nbundles += 1
      #puts "Node#{@id} created #{@nbundles} bundles"
    end

  end

end # module
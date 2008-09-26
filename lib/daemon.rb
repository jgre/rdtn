#!/usr/bin/env ruby
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

$:.unshift File.join(File.dirname(__FILE__))
# DTN daemon

require 'optparse'
require 'clientregcl'
require 'bundle'
require 'bundleworkflow'
require 'tcpcl'
require 'udpcl'
require 'flutecl'
require 'contactmgr'
require 'storage'
require 'configuration'
require "metablock"

module RdtnDaemon

  class Daemon

    attr_reader :evDis, :config

    def initialize(localEid = nil)
      @evDis = EventDispatcher.new
      @config = RdtnConfig.new(self)
      @config.localEid    = localEid if localEid
      @config.registerComponent(:localSender, self)

      Bundling::ParserManager.registerEvents(@evDis)
      Bundling::BundleWorkflow.registerEvents(@config, @evDis)
      Storage.new(@config, @evDis)
      ContactManager.new(@config, @evDis)
      # Create a default router
      RoutingTable.new(@config, @evDis)
      @configFileName     = File.join(File.dirname(__FILE__), "rdtn.conf")
      @localRegistrations = {} # EID -> AppProxy
      @links              = {}
      @interfaces         = {}
      @discoveries        = []

      @evDis.subscribe(:linkClosed) {|link| removeLink(link.name)}
    end

    def parseOptions(optParser = OptionParser.new)
      optParser.on("-c", "--config FILE", "config file name") do |c|
	@configFileName = c
      end
      optParser.on("-l", "--local EID", "local EID") do |l|
	@config.localEid = l
      end
      optParser.on("-s", "--stat-dir DIR", "Directory for statistics") do |s|
	@config.setStatDir(s)
      end
      optParser.parse!(ARGV)
    end

    def parseConfigFile(configFile = nil)
      configFile = configFile || @configFileName
      @config.load(configFile)
    end

    def runLoop
      rdebug("Starting DTN daemon main loop")
      sleep
    end

    def sendDataTo(data, eid, senderTag = nil)
      sendBundle(Bundling::Bundle.new(data, eid, makeLocalEid(senderTag)))
    end

    def sendBundle(bundle)
      bundle.srcEid = makeLocalEid(bundle.srcEid)
      @evDis.dispatch(:bundleParsed, bundle)
      bundle
    end

    def register(eid = nil, &handler)
      eid = makeLocalEid(eid).to_s
      @localRegistrations[eid] = AppIF::AppProxy.new(@config, @evDis, &handler)
      evDis.dispatch(:routeAvailable, RoutingEntry.new(eid, 
						      @localRegistrations[eid]))
    end

    def unregister(eid)
      eid = makeLocalEid(eid).to_s
      if @localRegistrations.include?(eid)
	@localRegistrations[eid].close
	@localRegistrations.delete(eid)
      end
    end

    def applicationAck(bundle)
      bdsr = BundleStatusReport::applicationAck(bundle)
      sendBundle(bdsr)
    end

    def makeLocalEid(part = nil)
      if not part
	@config.localEid
      elsif part.is_eid?
	part
      else
	# If the part is only a partial eid, prepend the eid of the router.
	@config.localEid.eid_append(part)
      end
    end

    def addLink(cl, name, options)
      lnkClass = CLReg.instance.cl[cl]
      if lnkClass
	link = lnkClass[1].new(@config, @evDis)
	link.open(name, options)
	rdebug("Adding #{cl} link #{link.name} with options: '#{options.to_a.join(' ')}'")
	@links[link.name] = link
	link
      else
	rerror("Unknown convergence layer: #{cl}")
      end
    end

    def removeLink(name)
      if @links[name]
	l = @links[name]
	@links.delete(name)
	l.close
      end
    end

    def addIf(cl, name, options = {})
      rdebug("Adding #{cl} interface #{name} with options: '#{options.to_a.join(' ')}'")
             
      ifClass = CLReg.instance.cl[cl]
      if ifClass
	interface = ifClass[0].new(@config, @evDis, name, options)
	@interfaces[name] = interface
	interface 
      else
	rerror("Unknown convergence layer: #{cl}")
      end
    end

    def router(type = nil, options = {})
      routerClass = nil
      if type
	routerClass = RouterReg.instance.routers[type]
	rerror("Unknown type of router: #{type}") unless routerClass
      end

      if routerClass
	rdebug("Starting router: #{type}") 
	routerClass.new(@config, @evDis, options)
      end
      @config.router
    end

    def addDiscovery(address, port, interval, announceIfs = [])
      ifs = announceIfs.map {|ifname| @interfaces[ifname]}
      ipd = IPDiscovery.new(@config, @evDis, address, port, interval, ifs)
      ipd.start
      ipd
    end

    def removeDiscovery(discovery)
      discovery.close if discovery
    end

    def addKasuariDiscovery(address, port, interval, announceIfs = [])
      ifs = announceIfs.map {|ifname| @interfaces[ifname]}
      ipd = KasuariDiscovery.new(@config, @evDis, address, port, interval, 
				 ifs)
      ipd.start
      ipd
    end

  end

end #module 

if $0 == __FILE__
  daemon = RdtnDaemon::Daemon.new
  daemon.parseOptions
  daemon.parseConfigFile
  daemon.runLoop
elsif $0 == "irb"
  $daemon = RdtnDaemon::Daemon.new
end

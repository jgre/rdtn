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
require "logger"
require 'routetab'
require 'singleton'
require 'tcpcl'
require 'udpcl'
require 'flutecl'
require 'clientregcl'
require 'discovery'
require 'priorityrouter'
require 'custodytimer'

module RdtnConfig

  class Reader

    :debug
    :info
    :error
    :warn
    :fatal


    :add

    :tcp
    :client

    :ondemand
    :alwayson


    def initialize
      @interfaces = {}
    end

    def self.load(filename)
      conf = new
      conf.instance_eval(File.read(filename), filename)
      conf
    end

    def loglevel(level, pattern = nil)

      curLevel = case level
		 when :debug: Logger::DEBUG
		 when :info : Logger::INFO
		 when :error: Logger::ERROR
		 when :warn : Logger::WARN
		 when :fatal: Logger::FATAL
		 else Logger:ERROR
		 end
      
      RdtnConfig::Settings.instance.setLogLevel(pattern, curLevel)
    end

    def log(level, msg)
      case level
      when :debug: rdebug(self, msg)
      when :info:  rinfo(self, msg)
      when :warn:  rwarn(self, msg)
      when :error: rerror(self, msg)
      when :fatal: rfatal(self, msg)
      else rinfo(self, msg)
      end
    end


    def self.hash_to_optString(hash={})
      options = []
      hash.each do |k, v|
	case k
	when :port: options << "-p #{v}" #TODO test 0 < int(v) < 65536
	when :host: options << "-h #{v}" #TODO no blanks in string v
	else
	  raise ArgumentError, "Unknown hash key: #{k}."
	end
      end
      return options.join(" ")
    end


    def interface(action, cl, name, options={})
      #options = RDTNConf::hash_to_optString(optionHash)

      case action
      when :add: addIf(cl, name, options)
      when :remove: rmIf(cl, name, options)
      else raise "syntax error: interface #{action}"
      end
    end

    def link(action, cl, name, options = {})
      case action
      when :add: addLink(cl, name, options)
      when :remove: rmLink(cl, name, options)
      else raise "syntax error: link #{action}"
      end
    end

    def discovery(action, address, port, interval, announceIfs = [])
      case action
      when :add
	ifs = announceIfs.map {|ifname| @interfaces[ifname]}
	ipd = IPDiscovery.new(address, port, interval, ifs)
	ipd.start
      when :kasuari
	ifs = announceIfs.map {|ifname| @interfaces[ifname]}
	ipd = KasuariDiscovery.new(address, port, interval, ifs)
	ipd.start
      else raise "syntax error: link #{action}"
      end
    end

    def storageDir(limit, dir)
      Settings.instance.store = Storage.new(limit, dir)
    end

    def localEid(eid)
      Settings.instance.localEid = EID.new(eid)
    end

    def route(action, dest, link)
      case action
      when :add: addRoute(dest, link)
      when :remove: rmRoute(dest, link)
      else raise "syntax error: link #{action}"
      end
    end

    def router(type)
      case type
      when :routingTable: 
	Settings.instance.router = RoutingTable.new(
	  Settings.instance.contactManager)
      when :priorityRouter 
	Settings.instance.router = PriorityRouter.new(
	  Settings.instance.contactManager)
      else raise "Unknown type of router #{type}"
      end
    end

    def addPriority(prio)
      prioAlg = PrioReg.instance.makePrio(prio)
      Settings.instance.router.addPriority(prioAlg)
      Settings.instance.store.addPriority(prioAlg)
    end

    def addFilter(filter)
      filterAlg = PrioReg.instance.makeFilter(filter)
      Settings.instance.router.addFilter(filterAlg)
    end

    def sprayWaitCopies(nCopies)
      Settings.instance.sprayWaitCopies = nCopies
    end

    private

    def addIf(cl, name, options)
      log(:debug, "adding interface #{name} for CL #{cl} with options: '#{options}'")

      clreg = CLReg.instance()

      ifClass = clreg.cl[cl]

      if (ifClass)
	interface = ifClass[0].new(name, options)
	@interfaces[name] = interface
      else
	log(:error, "no such convergence layer: #{cl}")
      end

    end


    def addLink(cl, name, options)
      log(:debug, "adding link #{name} for CL #{cl} with options: '#{options}'")

      clreg = CLReg.instance()

      ifClass = clreg.cl[cl]

      if (ifClass)
	link = ifClass[1].new()
	link.open(name, options)
      else
	log(:error, "no such convergence layer: #{cl}")
      end

    end


    def addRoute(dest, link)
      log(:debug, "adding route to #{dest} over link #{link}")

      EventDispatcher.instance.dispatch(:routeAvailable, 
					RoutingEntry.new(dest, link))

    end




  end # class Reader

  class Settings
    include Singleton

    attr_accessor :localEid, :store, :router, 
      :contactManager, :subscriptionHandler,
      :sprayWaitCopies, :custodyTimer

    def initialize
      @localEid = ""
      @store = nil
      @logLevels = []
      @defaultLogLevel = Logger::ERROR
    end

    def contactManager
      @contactManager  = ContactManager.new unless @contactManager
      return @contactManager
    end

    def subscriptionHandler
      @subscriptionHandler = SubscriptionHandler.new(nil) unless @subscriptionHandler
      return @subscriptionHandler
    end
    
    def custodyTimer
      @custodyTimer = CustodyTimer.instance()
      return @custodyTimer
    end

    # Set the log level for for a given classname pattern.
    # If a logmessage is written from a class, the log level associated with the
    # longest pattern as passed to this function is used. E.g.:
    # setLogLevel(/TCP/, INFO)
    # setLogLevel(/TCPLink/, DEBUG)
    #
    # Log messages from class TCPLink will be written with level DEBUG; messages
    # from TCPInterface will use INFO. 
    # The default level is ERROR
    def setLogLevel(pattern, level)
      if pattern
	@logLevels.push([pattern, level])
      else
	@defaultLogLevel = level
      end
    end

    def getLogger(classname)
      matchedLevel = nil
      matchedLen   = 0
      @logLevels.each do |pattern, level|
	if pattern =~ classname
	  if not matchedLevel or matchedLen < $&.length
	    matchedLevel = level
	    machtLen = $&.length
	  end
	end
      end
      @logger = Logger.new(STDOUT) unless @logger
      @logger.level = matchedLevel ? matchedLevel : @defaultLogLevel
      return @logger
    end

  end

end #module RdtnConfig

def rdebug(obj, *args)
  log = RdtnConfig::Settings.instance.getLogger(obj.class.name)
  log.debug(*args)
end

def rinfo(obj, *args)
  log = RdtnConfig::Settings.instance.getLogger(obj.class.name)
  log.info(*args)
end

def rwarn(obj, *args)
  log = RdtnConfig::Settings.instance.getLogger(obj.class.name)
  log.warn(*args)
end

def rerror(obj, *args)
  log = RdtnConfig::Settings.instance.getLogger(obj.class.name)
  log.error(*args)
end

def rfatal(obj, *args)
  log = RdtnConfig::Settings.instance.getLogger(obj.class.name)
  log.fatal(*args)
end

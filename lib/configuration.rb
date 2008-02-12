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
require 'tcpcl'
require 'udpcl'
require 'flutecl'
require 'clientregcl'
require 'discovery'
require 'priorityrouter'
require 'custodytimer'
require 'subscriptionhandler'

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


    def initialize(settings, evDis)
      @interfaces = {}
      @settings = settings
      @evDis = evDis
    end

    def self.load(evDis, filename, settings = Settings.new)
      conf = new(settings, evDis)
      conf.instance_eval(File.read(filename), filename)
      settings
    end

    def loglevel(level, pattern = nil)

      curLevel = case level
		 when :debug then Logger::DEBUG
		 when :info  then Logger::INFO
		 when :error then Logger::ERROR
		 when :warn  then Logger::WARN
		 when :fatal then Logger::FATAL
		 else Logger::ERROR
		 end
      
      @settings.setLogLevel(pattern, curLevel)
    end

    def log(level, msg)
      case level
      when :debug then rdebug(self, msg)
      when :info  then  rinfo(self, msg)
      when :warn  then  rwarn(self, msg)
      when :error then rerror(self, msg)
      when :fatal then rfatal(self, msg)
      else rinfo(self, msg)
      end
    end


    def self.hash_to_optString(hash={})
      options = []
      hash.each do |k, v|
	case k
	when :port then options << "-p #{v}" #TODO test 0 < int(v) < 65536
	when :host then options << "-h #{v}" #TODO no blanks in string v
	else
	  raise ArgumentError, "Unknown hash key: #{k}."
	end
      end
      return options.join(" ")
    end


    def interface(action, cl, name, options={})
      #options = RDTNConf::hash_to_optString(optionHash)

      case action
      when :add    then addIf(cl, name, options)
      when :remove then rmIf(cl, name, options)
      else raise "syntax error: interface #{action}"
      end
    end

    def link(action, cl, name, options = {})
      case action
      when :add    then addLink(cl, name, options)
      when :remove then rmLink(cl, name, options)
      else raise "syntax error: link #{action}"
      end
    end

    def discovery(action, address, port, interval, announceIfs = [])
      case action
      when :add
	ifs = announceIfs.map {|ifname| @interfaces[ifname]}
	ipd = IPDiscovery.new(@settings, @evDis, address, port, interval, ifs)
	ipd.start
      when :kasuari
	ifs = announceIfs.map {|ifname| @interfaces[ifname]}
	ipd = KasuariDiscovery.new(@settings, @evDis, address, port, interval, 
				   ifs)
	ipd.start
      else raise "syntax error: link #{action}"
      end
    end

    def storageDir(limit, dir)
      @settings.store = Storage.new(@evDis, limit, dir)
    end

    def localEid(eid)
      @settings.localEid = EID.new(eid) unless @settings.localEid
    end

    def route(action, dest, link)
      case action
      when :add    then addRoute(dest, link)
      when :remove then rmRoute(dest, link)
      else raise "syntax error: link #{action}"
      end
    end

    def router(type)
      case type
      when :routingTable 
	@settings.router = RoutingTable.new(@settings, @evDis,
					    @settings.contactManager)
      when :priorityRouter 
	# FIXME generic code to create the objects needed for a router config
	@settings.router = PriorityRouter.new(@settings, @evDis,
	  @settings.contactManager, @settings.subscriptionHandler)
      else raise "Unknown type of router #{type}"
      end
    end

    def addPriority(prio)
      #FIXME
      prioAlg = PrioReg.instance.makePrio(prio, @settings, @evDis, @settings.subscriptionHandler)
      @settings.router.addPriority(prioAlg)
      @settings.store.addPriority(prioAlg)
    end

    def addFilter(filter)
      #FIXME
      filterAlg = PrioReg.instance.makeFilter(filter, @settings, @evDis, @settings.subscriptionHandler)
      @settings.router.addFilter(filterAlg)
    end

    def sprayWaitCopies(nCopies)
      @settings.sprayWaitCopies = nCopies
    end

    def acceptCustody(custody)
      puts "#{custody} #{custody.class}"
      @settings.acceptCustody = custody
    end
    
    private

    def addIf(cl, name, options)
      log(:debug, "adding interface #{name} for CL #{cl} with options: '#{options}'")

      clreg = CLReg.instance()

      ifClass = clreg.cl[cl]

      if (ifClass)
	interface = ifClass[0].new(@settings, @evDis, name, options)
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
	link = ifClass[1].new(@settings, @evDis)
	link.open(name, options)
      else
	log(:error, "no such convergence layer: #{cl}")
      end

    end

    def addRoute(dest, link)
      log(:debug, "adding route to #{dest} over link #{link}")
      @evDis.dispatch(:routeAvailable, RoutingEntry.new(dest, link))
    end

  end # class Reader

  class Settings

    attr_accessor :localEid, :store, :router, 
      :contactManager, :subscriptionHandler,
      :sprayWaitCopies, :custodyTimer, :acceptCustody

    def initialize(evDis)
      # FIXME no big hairy object
      @evDis = evDis
      @localEid = nil
      @store = nil
      @logLevels = []
      @defaultLogLevel = Logger::ERROR
    end

    def contactManager
      @contactManager  = ContactManager.new(self, @evDis) unless @contactManager
      return @contactManager
    end

    def subscriptionHandler
      unless @subscriptionHandler
	@subscriptionHandler = SubscriptionHandler.new(self, @evDis,
						       contactManager)
      end
      return @subscriptionHandler
    end
    
    def custodyTimer
      @custodyTimer = CustodyTimer.new(self, @evDis) unless @custodyTimer
      return @custodyTimer
    end

    # Set the log level for for a given classname.
    # The default level is ERROR
    def setLogLevel(pattern, level)
      $rdtnLogLevels[pattern] = level
    end

  end

end #module RdtnConfig

$rdtnLogLevels = {nil => Logger::ERROR}
$rdtnLogger    = Logger.new(STDOUT)

def rdtnSetLogLevel(clsname)
  $rdtnLogger.level = $rdtnLogLevels[clsname] || $rdtnLogLevels[nil]
end

def rdebug(obj, *args)
  rdtnSetLogLevel(obj.class.name)
  $rdtnLogger.debug(*args)
end

def rinfo(obj, *args)
  rdtnSetLogLevel(obj.class.name)
  $rdtnLogger.info(*args)
end

def rwarn(obj, *args)
  rdtnSetLogLevel(obj.class.name)
  $rdtnLogger.warn(*args)
end

def rerror(obj, *args)
  rdtnSetLogLevel(obj.class.name)
  $rdtnLogger.error(*args)
end

def rfatal(obj, *args)
  rdtnSetLogLevel(obj.class.name)
  $rdtnLogger.fatal(*args)
end

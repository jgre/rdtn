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
require 'epidemicrouter'
require 'custodytimer'
require 'subscriptionhandler'

RDTNAPPIFPORT=7777

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


    def initialize(settings, evDis, daemon)
      @settings = settings
      @evDis = evDis
      @daemon = daemon
    end

    def self.load(evDis, filename, daemon, settings = Settings.new)
      conf = new(settings, evDis, daemon)
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

    def interface(action, cl, name, options={})
      case action
      when :add    then @daemon.addIf(cl, name, options)
      when :remove then @daemon.rmIf(cl, name, options)
      else raise "syntax error: interface #{action}"
      end
    end

    def link(action, cl, name, options = {})
      case action
      when :add    then @daemon.addLink(cl, name, options)
      when :remove then @daemon.rmLink(cl, name, options)
      else raise "syntax error: link #{action}"
      end
    end

    def discovery(action, address, port, interval, announceIfs = [])
      case action
      when :add
	@daemon.addDiscovery(address, port, interval, announceIfs)
      when :kasuari
	@daemon.addKasuariDiscovery(address, port, interval, announceIfs)
      else raise "syntax error: link #{action}"
      end
    end

    def storageDir(limit, dir)
      @settings.store = Storage.new(@evDis, limit, dir)
    end

    def statDir(dir)
      @settings.setStatDir(dir) unless @settings.stats
    end

    def localEid(eid)
      @settings.localEid = eid unless @settings.localEid
    end

    def route(action, dest, link)
      rwarn(self, "Configuration action 'route' is depricated. Use router.addRoute instead. #{caller(1)[0]}")
      case action
      when :add    then addRoute(dest, link)
      else raise "syntax error: link #{action}"
      end
    end

    def router(type = nil)
      @daemon.router(type)
    end

    def addPriority(prio)
      rwarn(self, "Configuration action 'addPriority' is depricated. Use router.addPriority instead. #{caller(1)[0]}")
      prioAlg = PrioReg.instance.makePrio(prio, @settings, @evDis, @settings.subscriptionHandler)
      @settings.router.addPriority(prioAlg)
      @settings.store.addPriority(prioAlg)
    end

    def addFilter(filter)
      rwarn(self, "Configuration action 'addFilter' is depricated. Use router.addFilter instead. #{caller(1)[0]}")
      filterAlg = PrioReg.instance.makeFilter(filter, @settings, @evDis, @settings.subscriptionHandler)
      @settings.router.addFilter(filterAlg)
    end

    def acceptCustody(custody)
      @settings.acceptCustody = custody
    end
    
    private

    def addRoute(dest, link)
      log(:debug, "adding route to #{dest} over link #{link}")
      @evDis.dispatch(:routeAvailable, RoutingEntry.new(dest, link))
    end

  end # class Reader

  class Settings

    attr_accessor :localEid, :acceptCustody
    Struct.new('Component', :component, :replacementAction)

    def initialize
      @localEid = nil
      @logLevels = []
      @defaultLogLevel = Logger::ERROR
      @acceptCustody = false
      @components = {}
    end

    # Set the log level for for a given classname.
    # The default level is ERROR
    def setLogLevel(pattern, level)
      $rdtnLogLevels[pattern] = level
    end

    def registerComponent(name, component, &replacementAction)
      if comp = @components[name] and comp.replacementAction
        comp.replacementAction[]
      else
        self.class.class_eval {define_method(name) {self.component(name)}}
      end
      @components[name] = Struct::Component.new(component, replacementAction)
    end

    def component(name)
      @components[name].component if @components[name]
    end

    def setStatDir(dir)
      dir = File.expand_path(dir)
      begin
	Dir.mkdir(dir) unless File.exist?(dir)
      rescue => ex
	rwarn(self, "Could not create statistics handler: #{ex}")
      else
	@stats = Stats::StatGrabber.new(@evDis,
					File.join(dir, "time.stat"),
					File.join(dir, "out.stat"),  
					File.join(dir, "in.stat"),
					File.join(dir, "contact.stat"),
					File.join(dir, "subscribe.stat"),
					File.join(dir, "store.stat"))
      end
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

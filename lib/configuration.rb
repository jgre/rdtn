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

class RdtnConfig

  attr_writer :localEid, :acceptCustody
  Struct.new('Component', :component, :replacementAction)

  def initialize(daemon = nil)
    @localEid = nil
    @logLevels = []
    @defaultLogLevel = Logger::ERROR
    @acceptCustody = false
    @components = {}
    @daemon = daemon
  end

  def self.load(filename, daemon)
    new(daemon).load(filename)
  end

  def load(filename)
    instance_eval(File.read(filename))
    self
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

    setLogLevel(pattern, curLevel)
  end

  def log(level, msg)
    case level
    when :debug then rdebug(self, msg)
    when :info  then rinfo(self, msg)
    when :warn  then rwarn(self, msg)
    when :error then rerror(self, msg)
    when :fatal then rfatal(self, msg)
    else rinfo(self, msg)
    end
  end

  def interface(*args)
    if [:add, :remove].include?(args[0])
      puts "The action paramter for #{self.class}#interface is depricated."
      puts "Use 'interface CL, NAME, OPTIONS'"
      args.delete_at 0
    end
    _interface(*args)
  end

  def _interface(cl, name, options={})
    @daemon.addIf(cl, name, options)
  end

  def link(*args)
    if [:add, :remove].include?(args[0])
      puts "The action paramter for #{self.class}#link is depricated."
      puts "Use 'link CL, NAME, OPTIONS'"
      args.delete_at 0
    end
    _link(*args)
  end

  def _link(cl, name, options = {})
    @daemon.addLink(cl, name, options)
  end

  def discovery(*args)
    if [:add, :kasuari].include?(args[0])
      puts "The action paramter for #{self.class}#discovery is depricated."
      puts "Use 'discovery ADDRESS, PORT, INTERVAL, INTERFACES'"
      args.delete_at 0
    end
    _discovery(*args)
  end

  def _discovery(address, port, interval, announceIfs = [])
    @daemon.addDiscovery(address, port, interval, announceIfs)
  end

  def storageDir(limit, dir)
    Storage.new(@settings, @evDis, limit, dir)
  end

  def localEid(eid = nil)
    @localEid = eid if eid
    @localEid
  end

  def acceptCustody(accept = nil)
    @acceptCustody = accept unless accept.nil?
    @acceptCustody
  end

  def route(action, dest, link)
    rwarn(self, "Configuration action 'route' is depricated. Use router.addRoute instead. #{caller(1)[0]}")
    case action
    when :add    then addRoute(dest, link)
    else raise "syntax error: link #{action}"
    end
  end

  def router(type = nil, options = {})
    @daemon.router(type)
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

end

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

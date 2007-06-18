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
#
# $Id: fileup.py 8 2006-12-22 20:00:21Z jgre $

require 'rdtnlog'
require 'cl'
require 'routetab'
require 'singleton'

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


    def self.load(filename)
      conf = new
      conf.instance_eval(File.read(filename), filename)
      conf.loglevel(:debug)
      conf
    end

    def loglevel(level)
      @lg=RdtnLogger.instance()    

      lv={
	:debug => Logger::DEBUG,
	:info  => Logger::INFO,
	:error => Logger::ERROR,
	:warn  => Logger::WARN,
	:fatal => Logger::FATAL
      }

      @lg.level=lv[level] || Logger::UNKOWN

    end

    def log(level, msg)
      case level
      when :debug: @lg.debug(msg)
      when :info: @lg.info(msg)
      when :warn: @lg.warn(msg)
      when :error: @lg.error(msg)
      when :fatal: @lg.fatal(msg)
      else @lg.info(msg)
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
      puts "IF func: #{action}, #{name}"
      #options = RDTNConf::hash_to_optString(optionHash)

      case action
      when :add: addIf(cl, name, options)
      when :remove: rmIf(cl, name, options)
      else raise "syntax error: interface #{action}"
      end
    end

    def link(action, cl, name, options)
      case action
      when :add: addLink(cl, name, options)
      when :remove: rmLink(cl, name, options)
      else raise "syntax error: link #{action}"
      end
    end

    def storageDir(dir)
      puts "StorageDir = #{dir}"
      Settings.instance.storageDir = dir
    end

    def localEid(eid)
      puts "LocalEid = #{eid}"
      Settings.instance.localEid = eid
    end

    def route(action, dest, link)
      case action
      when :add: addRoute(dest, link)
      when :remove: rmRoute(dest, link)
      else raise "syntax error: link #{action}"
      end
    end

    private

    def addIf(cl, name, options)
      log(:debug, "adding interface #{name} for CL #{cl} with options: '#{options}'")

      clreg = CLReg.instance()

      ifClass = clreg.cl[cl]

      if (ifClass)
	interface = ifClass[0].new(name, options)
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

      RoutingTable.instance().addEntry(dest,link)

    end




  end # class Reader

  class Settings
    include Singleton

    attr_accessor :localEid, :storageDir

    def initialize
      @localEid = ""
      @storageDir = "store"
    end
  end

end #module RdtnConfig

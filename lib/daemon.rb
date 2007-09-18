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
require 'bundle'
require 'tcpcl'
require 'udpcl'
require 'flutecl'
require 'contactmgr'
require 'storage'
require 'clientregcl'
require 'configuration'
require "stats"

module RdtnDaemon

  class Daemon

    def initialize(optParser = OptionParser.new)

      @log = RdtnConfig::Settings.instance.getLogger(self.class.name)
      Bundling::ParserManager.registerEvents

      configFileName=File.join(File.dirname(__FILE__),"rdtn.conf")

      optParser.on("-c", "--config FILE", "config file name") do |c|
	configFileName = c
      end
      optParser.on("-s", "--stat-dir DIR", "Directory for statistics") do |s|
	dir = File.expand_path(s)
	begin
	  Dir.mkdir(dir)
	rescue
	end
	stats = Stats::StatGrabber.new(File.join(dir, "out.stat"),  
				       File.join(dir, "in.stat"))
      end

      optParser.parse!(ARGV)
      
      # Initialize Contact manager and routing table
      cmgr = ContactManager.new
      router = RoutingTable.new(cmgr)
      store = RdtnConfig::Settings.instance.store
      conf = RdtnConfig::Reader.load(configFileName)

    end

    def runLoop
      @log.debug("Starting DTN daemon main loop")
      sleep # Let the other threads run until the process is killed.
    end
  end

end #module 

if $0 == __FILE__
  RdtnDaemon::Daemon.new.runLoop
end



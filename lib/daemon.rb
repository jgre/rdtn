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

$:.unshift File.join(File.dirname(__FILE__))
# DTN daemon

require 'optparse'
require 'bundle'
require 'tcpcl'
require 'udpcl'
require 'flutecl'
require 'rdtnlog'
require 'contactmgr'
require 'storage'
require 'clientregcl'
require 'rdtnconf'
#require "router"

log=RdtnLogger.instance()
log.level=Logger::DEBUG
RDTNConfig.instance.localEid = "dtn://bla.fasel"
bl = Bundling::BundleLayer.new


configFileName="rdtn.conf"

opts = OptionParser.new do |opts|
  opts.on("-c", "--config FILE", "config file name") do |c|
    configFileName = c
  end
end

opts.parse!(ARGV)



# Initialize Contact manager and routing table
cmgr = ContactManager.instance
router = RoutingTable.instance
store = Storage.instance
conf = RDTNConf.load(configFileName)

log.debug("Starting DTN daemon main loop")
EventLoop.run()




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
# $Id$

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
require "stats"

log=RdtnLogger.instance()
log.level=Logger::DEBUG
#RDTNConfig.instance.localEid = "dtn://bla.fasel"
bl = Bundling::BundleLayer.new
stats = Stats::StatGrabber.new("out.stat", "in.stat")

configFileName="rdtn.conf"
loopInterval = 10
duration = 1
dest = "dtn://hamlet.dtn/test"

opts = OptionParser.new do |opts|
  opts.on("-c", "--config FILE", "config file name") do |c|
    configFileName = c
  end
  opts.on("-d", "--dest EID", "destination EID") do |d|
    dest=d
  end
  opts.on("-l", "--local EID", "local EID") do |l|
    RDTNConfig.instance.localEid = EID.new(l)
  end
  opts.on("-L", "--loop INTERVAL", Integer) do |val|
    loopInterval = val
  end
  opts.on("-D", "--duration SECONDS", Integer) do |val|
    duration = val
  end
end

opts.parse!(ARGV)

if not ARGV.empty?
  plFile = open(ARGV[0])
else
  plFile = $stdin
end

payload=plFile.read
plFile.close
puts "Payload length: #{payload.length}"

# Initialize Contact manager and routing table
cmgr = ContactManager.instance
router = RoutingTable.instance
store = Storage.instance
conf = RDTNConf.load(configFileName)

b = Bundling::Bundle.new(payload)
b.destEid = EID.new(dest)
log.debug("sending bundle")
EventDispatcher.instance().dispatch(:bundleParsed, b)

EventLoop.after(duration) do
  log.debug("Stopping notifier")
  EventLoop.quit()
end

if defined?(loopInterval)
  EventLoop.every(loopInterval.seconds) do
    b = Bundling::Bundle.new(payload)
    b.destEid = EID.new(dest)
    log.debug("sending bundle")
    EventDispatcher.instance().dispatch(:bundleParsed, b)
  end
end

log.debug("Starting DTN daemon main loop")
EventLoop.run()




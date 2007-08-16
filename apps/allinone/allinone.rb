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

$:.unshift File.join(File.dirname(__FILE__), "..", "..", "lib")
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
require 'configuration'
require "stats"
require "daemon"

log=RdtnLogger.instance()
log.level=Logger::DEBUG

loopInterval = 10
duration = 1
dest = "dtn://hamlet.dtn/test"
terminationDelay = 0
interactive = false

opts = OptionParser.new do |opts|
  opts.on("-d", "--dest EID", "destination EID") do |d|
    dest=d
  end
  opts.on("-l", "--local EID", "local EID") do |l|
    RdtnConfig::Settings.instance.localEid = EID.new(l)
  end
  opts.on("-L", "--loop INTERVAL", Integer) do |val|
    loopInterval = val
  end
  opts.on("-D", "--duration SECONDS", Integer) do |val|
    duration = val
  end
  opts.on("-t", "--termination-delay SECONDS", "Delay termination after the last bundle was sent.", Integer) do |val|
    terminationDelay = val
  end
  opts.on("-i", "--interactive") do |val|
    interactive = true
  end
end

daemon = RdtnDaemon::Daemon.new(opts)

if not ARGV.empty?
  plFile = open(ARGV[0])
elsif interactive
  plFile = $stdin
end

if defined? plFile and plFile
  payload=plFile.read
  plFile.close

  b = Bundling::Bundle.new(payload)
  b.destEid = EID.new(dest)
  log.debug("sending bundle")
  EventDispatcher.instance().dispatch(:bundleParsed, b)

  if defined?(loopInterval)
    Thread.new(loopInterval) do |interv|
      while true
	sleep(interv)
	b = Bundling::Bundle.new(payload)
	b.destEid = EID.new(dest)
	log.debug("sending bundle")
	EventDispatcher.instance().dispatch(:bundleParsed, b)
      end
    end
  end

end
log.debug("Starting DTN daemon main loop")

#daemon.runLoop
sleep (duration)
log.debug("Stopping notifier")

ObjectSpace.each_object(Link) {|link| link.close}
ObjectSpace.each_object(Interface) {|iface| iface.close}
sleep(terminationDelay)
exit


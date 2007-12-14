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
$:.unshift File.join(File.dirname(__FILE__), "..", "lib")

require 'rdtnevent'
require 'singleton'
require 'socket'
require 'nodeconnection'
require 'remconf'
require 'setdestparser'
require 'optparse'
require 'timerengine'

module Rem

  class SimCore

    include Singleton

    def initialize(optParser = OptionParser.new)
      # id -> NodeConnection
      @nodes = {}
      @timeSock = UDPSocket.new

      configFileName= File.join(File.dirname(__FILE__), 'rem.conf')
      owNNodes      = nil
      owDuration    = nil
      owGranularity = nil
      optParser.on("-c", "--config FILE", "config file name") do |c|
	configFileName = c
      end
      optParser.on("-n", "--nnodes NODES", "Number of nodes") do |n|
	owNNodes = n.to_i
      end
      optParser.on("-d", "--duration SEONDS", 
                   "Emulation duration in seconds") do |d|
	owDuration = d.to_f
      end
      optParser.on("-g", "--granularity SECONDS", 
		   "Granularity in seconds") do |g|
	owGranularity = g.to_f
      end
      optParser.parse!(ARGV)
      conf = Config.load(configFileName)
      Config.instance.nnodes      = owNNodes if owNNodes
      puts "NNodes #{Config.instance.nnodes}"
      Config.instance.duration    = owDuration if owDuration
      Config.instance.granularity = owGranularity if owGranularity
    end

    def run
      endTime = Time.now + Config.instance.duration
      puts "Duration #{Config.instance.duration} #{endTime}"
      # Open incoming socket
      sock = TCPServer.new(Config.instance.host, 
			   Config.instance.port)

      # Start @nnodes rdtn processes
      forkRdtnProcesses
      # Wait for all @nnodes to connect
      acceptConnections(sock)
      EventDispatcher.instance.subscribe(:remTimerTick) do |time|
	Config.instance.time = time
	broadcastTime(time)
	shutdown if time >= endTime
      end
      EventDispatcher.instance.subscribe(:remConnection) do |nodeId1, nodeId2|
	node1 = @nodes[nodeId1]
	node2 = @nodes[nodeId2]
	if node1 and node2
	  puts "Core: Connect #{nodeId1} #{nodeId2}"
	  node1.connections[nodeId2] = node2
	  node2.connections[nodeId1] = node1
	  node1.connect(node2)
	  node2.connect(node1)
	end
      end
      EventDispatcher.instance.subscribe(:remDisconnection) do |nodeId1,nodeId2|
	node1 = @nodes[nodeId1]
	node2 = @nodes[nodeId2]
	if node1 and node2
	  puts "Core: Disconnect #{nodeId1} #{nodeId2}"
	  node1.disconnect(node2)
	  node2.disconnect(node1)
	end
      end
      te     = TimerEngine.new
      te.run
    end

    private

    def forkRdtnProcesses
      @pids = []
      1.upto(Config.instance.nnodes) do |n|
	Dir.mkdir("kasuari#{n}") unless File.exist?("kasuari#{n}")
	@pids.push fork {exec("/usr/bin/env ruby #{Config.instance.rdtnPath} -c #{Config.instance.configPath} -l dtn://kasuari#{n}/ -s kasuari#{n} --port #{7777+n}")} # > kasuari#{n}/rdtn.log")}
      end
    end

    def acceptConnections(sock)
      puts "Accepting connections..."
      while @nodes.length < Config.instance.nnodes
	nodeSock = sock.accept
	conn = NodeConnection.new(nodeSock)
	@nodes[conn.id] = conn
	puts "Accepted node #{conn.id}"
      end
    end

    def broadcastTime(time)
      data = [time.to_f].pack('G')
      @timeSock.send(data, 0, Config.instance.timeAddr, 
		     Config.instance.timePort)
    end

    def shutdown
      puts "Shutdown"
      @nodes.each {|id, node| node.shutdown}
      @pids.each {|pid| Process.kill("HUP", pid)}
      Process.waitall
      exit(0)
    end

  end

end # module rem

if $0 == __FILE__
  Rem::SimCore.instance.run
end

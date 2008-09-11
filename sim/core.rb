#!/usr/bin/env ruby
#  Copyright (C) 2007, 2008 Janico Greifenberg <jgre@jgre.org> and 
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
require 'nodeconnection'
require 'optparse'
require 'timerengine'
require 'yaml'
require 'logentry'

module Sim

  class Core

    attr_reader   :config, :nodes
    attr_accessor :events

    DEFAULT_CONF = {
      "nnodes"      => 10,
      "duration"    => 600,
      "granularity" => 0.1,
      "realTime"    => false,
      "bytesPerSec" => 1024,
    }

    def initialize(dirName = nil)
      @evDis = EventDispatcher.new
      # id -> NodeConnection
      @nodes = {}
      @log   = []
      @timerEventId = 0
      @config = DEFAULT_CONF 
      @config["dirName"] = dirName
      # Hash of configuration options that should overwrite setting from the
      # config file
      @owConf = {}
      if dirName
	@owConf["dirName"] = dirName
	Dir.mkdir(@config["dirName"]) unless File.exist?(@config["dirName"])
      end

      @configFileName = File.join(File.dirname(__FILE__), 'sim.conf')
      @events = EventQueue.new
      @te = TimerEngine.new(@config, @evDis)

      @evDis.subscribe(:simConnection) do |nodeId1, nodeId2|
	node1 = @nodes[nodeId1]
	node2 = @nodes[nodeId2]
	node1.connect(node2) if node1 and node2
      end
      @evDis.subscribe(:simDisconnection) do |nodeId1,nodeId2|
	node1 = @nodes[nodeId1]
	node2 = @nodes[nodeId2]
	node1.disconnect(node2) if node1 and node2
      end
    end

    def parseConfigFile(configFile = nil)
      configFile = configFile || @configFileName
      @config.merge!(open(configFile) {|f| YAML.load(f)})
      @config.merge!(@owConf)
      if @config["eventdump"] and File.exist?(@config["eventdump"])
	loadEventdump(@config["eventdump"])
      elsif @config["traceParser"]
	traceParser(@config["duration"], @config["granularity"],
                    @config["traceParser"])
      end
      Dir.mkdir(@config["dirName"]) unless File.exist?(@config["dirName"])
    end

    def parseOptions(optParser = OptionParser.new)
      optParser.on("-c", "--config FILE", "config file name") do |c|
	@configFileName = c
      end
      optParser.on("-n", "--nnodes NODES", "Number of nodes") do |n|
	@owConfg["nnodes"] = n.to_i
      end
      optParser.on("-d", "--duration SEONDS", 
                   "Simulation duration in seconds") do |d|
	@owConf["duration"] = d.to_f
      end
      optParser.on("-g", "--granularity SECONDS", 
		   "Granularity in seconds") do |g|
	@owConf["granularity"] = g.to_f
      end
      optParser.parse!(ARGV)
      @config.merge!(@owConf)
    end

    def loadEventdump(filename)
      open(filename) {|f| @events = Marshal.load(f) }
    end

    def at(time)
      @timerEventId += 1
      sym = "timerEvent#@timerEventId".to_sym
      @events.addEventSorted(time, nil, nil, sym)
      ev = @evDis.subscribe(sym) do |t|
	repeat = yield(t)
	if repeat
	  @events.addEventSorted(t + time, nil, nil, sym)
	else
	  @evDis.unsubscribe(sym, ev)
	end
      end
      sym
    end

    def after(time)
      at(@te.timer + time) {|t| yield(t)}
    end

    def node(id)
      @nodes[id]
    end

    def log(eventId, nodeId1, nodeId2, options = {})
      @log.push(LogEntry.new(time, eventId, nodeId1, nodeId2, options))
    end

    def run(duration = nil, startTime = 0)
      dur = duration || @config["duration"]
      @endTime = startTime + dur
      rinfo(self, "Starting simulation with #{@config["nnodes"]} simulation nodes starting at time #{startTime}. Duration: #{dur} seconds.")

      RdtnTime.timerFunc = lambda {@te.time}

      @te.run(dur, @events, startTime)
      [@events, @log]
    end

    def createNodes(nodeNames = nil)
      nodeNames = nodeNames || (1..@config["nnodes"]).to_a
      nodeNames = (1..nodeNames).to_a if nodeNames.class == Fixnum
      nodeNames.each do |n|
	@nodes[n] = Node.new(@config["dirName"], n, self,
			     @config["bytesPerSec"],
			     @config["rdtnConfPath"])
      end
    end

    def time
      @te.timer if @te
    end

  end

end # module sim

if $0 == __FILE__
  dirName = File.join(Dir.getwd, 
			  "experiment#{Time.now.strftime('%Y%m%d-%H%M%S')}")
  sim = Sim::Core.new(dirName)
  sim.parseOptions
  sim.parseConfigFile
  sim.createNodes
  sim.run
elsif $0 == "irb"
  dirName = File.join(Dir.getwd, 
			  "irb-experiment#{Time.now.strftime('%Y%m%d-%H%M%S')}")
  $sim = Sim::Core.new(dirName)
end

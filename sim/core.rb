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
require 'nodeconnection'
require 'setdestparser'
require 'optparse'
require 'timerengine'
require 'yaml'
require 'traceparser'

module Sim

  class SimCore

    attr_reader :config, :nodes

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
      #@config = Sim::Config.new(@evDis)
      @config = DEFAULT_CONF 
      @config["dirName"] = dirName
      # Hash of configuration options that should overwrite setting from the
      # config file
      @owConf = {}
      if dirName
	@owConf["dirName"] = dirName
	Dir.mkdir(@config["dirName"]) unless File.exist?(@config["dirName"])
      end
      @nConnect = @nDisconnect = 0
      @configFileName= File.join(File.dirname(__FILE__), 'sim.conf')
      @events = nil
      @te = TimerEngine.new(@config, @evDis)

      #@channels = (1..@config.nchannels).to_a.map {|i| "dtn://channel#{i}/"}
      #@senders = {}
      #@channels.each_with_index {|ch, i| @senders[i+1] = ch}
      ##FIXME make this configurable (pareto distribution)
      #@receivers = {
      #    6  => ["dtn://channel1/", "dtn://channel2/"],
      #    7  => ["dtn://channel2/", "dtn://channel3/", "dtn://channel4/"],
      #    8  => ["dtn://channel4/", "dtn://channel5/", "dtn://channel1/"],
      #    9  => ["dtn://channel4/", "dtn://channel5/", "dtn://channel1/"],
      #    10 => ["dtn://channel5/", "dtn://channel1/"]
      #}
      @evDis.subscribe(:simTimerTick) do |time|
	#if (time.to_i-startTime.to_i) % @config.bundleInterval == 0
	#  
	#  @senders.each do |id, channel| 
	#    @nodes[id].createBundle(channel) if @nodes[id]
	#  end

	#  #puts "Running for #{time-startTime} seconds (#{(time-startTime).to_f/@config.duration * 100}%), #{endTime-time} seconds left."
	#end
	@nodes.each_value {|node| node.process(@config["granularity"])}
      end
      @evDis.subscribe(:simConnection) do |nodeId1, nodeId2|
	rdebug(self, "SimConnection #{nodeId1}, #{nodeId2}")
	@nConnect += 1
	node1 = @nodes[nodeId1]
	node2 = @nodes[nodeId2]
	node1.connect(node2) if node1 and node2
	#if node1 and node2
	#  Node.connect(node1, node2)
	#end
      end
      @evDis.subscribe(:simDisconnection) do |nodeId1,nodeId2|
	@nDisconnect += 1
	node1 = @nodes[nodeId1]
	node2 = @nodes[nodeId2]
	node1.disconnect(node2) if node1 and node2
	#puts "#{@config.time-startTime}, #{nodeId1}, #{nodeId2}, simDisconnection"
	#@eq.addEvent(Time.now.to_f, nodeId1, nodeId2, :simDisconnection)
	#puts "#{@eq.events.length} Core Events"
	#open("#{@config.dirName}/eventCoreDump", "w") {|f| Marshal.dump(@eq, f)}
	  #puts "Core: Disconnect #{nodeId1} #{nodeId2}"
	  #Node.disconnect(node1, node2)
	#end

      end
    end

    def parseConfigFile(configFile = nil)
      configFile = configFile || @configFileName
      @config.merge!(open(configFileName) {|f| YAML.load(f)})
      @config.merge!(@owConf)
      if @config["eventdump"]
	loadEventdump(@config["eventdump"])
      elsif @config["traceParser"]
	traceParser(@config["traceParser"])
      end
      Dir.mkdir(@config["dirName"]) unless File.exist?(@config["dirName"])
      #@config.load(configFileName)
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
      open(filename) {|f| self.events = Marshal.load(f) }
    end

    def traceParser(options)
      klass = TraceParserReg.instance.tps[options["type"]]
      if klass
	parser = klass.new(@config["duration"], @config["granularity"], options)
	self.events = parser.events
	if options["tracefile"]
	  open(File.basename(options["tracefile"], ".*")+".rdtnsim", "w") do |f|
	    Marshal.dump(@events, f)
	  end
	end
      else
	rerror(self, "Unknown type of traceparser #{options["type"]}")
      end
    end

    def events=(events)
      @events.stop(@evDis) if @events
      @events = events
      @events.register(@evDis)
    end

    def at(time = nil)
      ev = @evDis.subscribe(:simTimerTick) do |t|
	if time.nil? or t >= time
	  repeat = yield(t)
	  @evDis.unsubscribe(:simTimerTick, ev) unless repeat and time.nil?
	end
      end
    end

    def run(duration = nil, startTime = 0)
      dur = duration || @config["duration"]
      endTime = startTime + dur
      rinfo(self, "Starting simulation with #{@config["nnodes"]} simulation nodes starting at time #{startTime}. Duration: #{dur} seconds.")

      RdtnTime.timerFunc = lambda {@te.time}

      @te.run(dur, startTime)
    end

    def createNodes(nnodes = nil)
      nnodes = nnodes || @config["nnodes"]
      1.upto(nnodes) do |n|
	@nodes[n] = Node.new(@config["dirName"], n, @config["bytesPerSec"],
			     @config["rdtnConfPath"])
      end
    end

    #private

    #def shutdown
    #  rinfo(self, "Shutdown")
    #  rinfo(self, "#{@nConnect} connetct events")
    #  rinfo(self, "#{@nDisconnect} disconnetct events")
    #  exit(0)
    #end

  end

end # module sim

if $0 == __FILE__
  dirName = File.join(Dir.getwd, 
			  "experiment#{Time.now.strftime('%Y%m%d-%H%M%S')}")
  Sim::SimCore.new(dirName).run
elsif $0 == "irb"
  dirName = File.join(Dir.getwd, 
			  "irb-experiment#{Time.now.strftime('%Y%m%d-%H%M%S')}")
  $sim = Sim::SimCore.new(dirName)
end

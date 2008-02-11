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
require 'nodeconnection'
require 'conf'
require 'setdestparser'
require 'regulareventgen'
require 'optparse'
require 'timerengine'
require 'profiler'

module Sim

  class SimCore

    attr_reader :config

    include Singleton

    def initialize(optParser = OptionParser.new)
      @evDis = EventDispatcher.new
      # id -> NodeConnection
      @nodes = {}
      @nConnect = @nDisconnect = 0

      configFileName= File.join(File.dirname(__FILE__), 'sim.conf')
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
      @config = Config.load(@evDis, configFileName)
      @config.nnodes = owNNodes if owNNodes
      puts "NNodes #{config.nnodes}"
      @config.duration    = owDuration if owDuration
      @config.granularity = owGranularity if owGranularity

      @channels = (1..@config.nchannels).to_a.map {|i| "dtn://channel#{i}/"}
      @senders = {}
      @channels.each_with_index {|ch, i| @senders[i+1] = ch}
      #FIXME make this configurable (pareto distribution)
      @receivers = {
          6  => ["dtn://channel1/", "dtn://channel2/"],
          7  => ["dtn://channel2/", "dtn://channel3/", "dtn://channel4/"],
          8  => ["dtn://channel4/", "dtn://channel5/", "dtn://channel1/"],
          9  => ["dtn://channel4/", "dtn://channel5/", "dtn://channel1/"],
          10 => ["dtn://channel5/", "dtn://channel1/"]
      }


    end

    def run(dirName)
      @config.dirName = dirName
      Dir.mkdir(dirName) unless File.exist?(dirName)
      startTime = Time.now
      endTime = startTime + @config.duration
      puts "Duration #{@config.duration} #{endTime}"

      RdtnTime.timerFunc = lambda {@config.time}

      createNodes
      #@eq = EventQueue.new
      @evDis.subscribe(:simTimerTick) do |time|
	@config.time = time
	shutdown if time >= endTime
	# FIXME variate times for the different channels
	if (time.to_i-startTime.to_i) % @config.bundleInterval == 0
	  
	  @senders.each do |id, channel| 
	    @nodes[id].createBundle(channel) if @nodes[id]
	  end

	  puts "Running for #{time-startTime} seconds (#{(time-startTime).to_f/@config.duration * 100}%), #{endTime-time} seconds left."
	end
	@nodes.each_value {|node| node.process(@config.granularity)}
      end
      @evDis.subscribe(:simConnection) do |nodeId1, nodeId2|
	@nConnect += 1
	node1 = @nodes[nodeId1]
	node2 = @nodes[nodeId2]
	#puts "#{@config.time-startTime}, #{nodeId1}, #{nodeId2}, simConnection"
	#puts "#{@eq.events.length} Core Events"
	#open("#{@config.dirName}/eventCoreDump", "w") {|f| Marshal.dump(@eq, f)}
	if node1 and node2
	  #puts "Core: Connect #{nodeId1} #{nodeId2}"
	  Node.connect(node1, node2)
	end
      end
      @evDis.subscribe(:simDisconnection) do |nodeId1,nodeId2|
	@nDisconnect += 1
	node1 = @nodes[nodeId1]
	node2 = @nodes[nodeId2]
	#puts "#{@config.time-startTime}, #{nodeId1}, #{nodeId2}, simDisconnection"
	#@eq.addEvent(Time.now.to_f, nodeId1, nodeId2, :simDisconnection)
	#puts "#{@eq.events.length} Core Events"
	#open("#{@config.dirName}/eventCoreDump", "w") {|f| Marshal.dump(@eq, f)}
	if node1 and node2
	  #puts "Core: Disconnect #{nodeId1} #{nodeId2}"
	  Node.disconnect(node1, node2)
	end
      end
      te = TimerEngine.new(@config, @evDis)
      #Profiler__::start_profile
      te.run
    end

    private

    def createNodes
      1.upto(@config.nnodes) do |n|
	@nodes[n] = Node.new(@config, n, @receivers[n])
      end
    end

    def shutdown
      puts "Shutdown"
      puts "#{@nConnect} connetct events"
      puts "#{@nDisconnect} disconnetct events"
      #Profiler__::stop_profile
      #Profiler__::print_profile($stdout)
      exit(0)
    end

  end

end # module sim

if $0 == __FILE__
  dirName = File.join(Dir.getwd, 
			  "experiment#{Time.now.strftime('%Y%m%d-%H%M%S')}")
  Sim::SimCore.instance.run(dirName)
end

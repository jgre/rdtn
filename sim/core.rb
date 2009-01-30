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
require 'traceparser'
require 'stats/networkmodel'
require 'stats/trafficmodel'
require 'spec'
require 'graph'
require 'analysis'

module Sim

  class Core

    attr_reader   :nodes, :duration
    attr_accessor :events

    def initialize
      @evDis = EventDispatcher.new
      # id -> NodeConnection
      @nodes = {}

      # Add singleton methods to the nodes object, so you can call
      #   sim.nodes.router :epidemic
      # and
      #   sim.nodes.linkCapacity = 2048
      # to set epidemic routing and a link capacity of 2048 bytes per second
      # for all nodes simulated by the Sim::Core object sim.
      def @nodes.router(type = nil, options = {})
        each_value {|node| node.router(type, options)}
      end
      def @nodes.linkCapacity=(bytesPerSec)
        each_value {|node| node.linkCapacity = bytesPerSec}
      end
      def @nodes.storage_limit=(limit)
	each_value {|node| node.config.store.limit = limit}
      end
      def @nodes.subscription_range=(range)
	each_value {|node| node.router.subsRange = range if node.router.respond_to? :subsRange=}
      end

      RdtnTime.scheduleFunc = lambda {|sec, &handler| after(sec, &handler)}

      @traffic_model = TrafficModel.new(Time.now)
      @timerEventId  = 0

      @events = EventQueue.new
      @te     = TimerEngine.new(@evDis)

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

    def events=(events)
      @events = events
      createNodes(@events.nodeCount) if @nodes.empty?
      @duration = @events.last.time
    end

    TRACEDIR = File.join(File.dirname(__FILE__), '../simulations/traces')
    def trace(options = {})
      if options[:tracefile]
        options[:tracefile] = File.join(TRACEDIR, options[:tracefile])
      end
      self.events = Sim.traceParser(options)
    end

    def loadEventdump(filename)
      open(filename) {|f| self.events = Marshal.load(f) }
    end

    def at(time)
      @timerEventId += 1
      sym = "timerEvent#@timerEventId".to_sym
      @events.addEventSorted(time, nil, nil, sym)
      ev = @evDis.subscribe(sym) do |t|
	repeat = yield(t)
	if repeat and (t + time).to_i <= @duration.to_i
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
      @traffic_model.event(LogEntry.new(time,eventId,nodeId1,nodeId2,options))
    end

    def run
      old_timer_func     = RdtnTime.timerFunc
      RdtnTime.timerFunc = lambda {@te.time}

      @te.run(@events)

      RdtnTime.timerFunc = old_timer_func

      [@events, @traffic_model]
    end

    def createNodes(nodeNames = nil)
      nodeNames = (1..nodeNames).to_a if nodeNames.class == Fixnum
      nodeNames.each {|n| @nodes[n] = Node.new(n, self)}
    end

    def time
      @te.timer if @te
    end

    def self.runBySpec(spec, dir)
      sim     = new

      spec = Specification.loadSpec(spec).new unless spec.is_a?(Specification)

      dirname = File.join(dir, spec.name)
      FileUtils.mkdir_p(dirname)

      t0 = Time.now

      spec.execute(sim)

      events, traffic_model = sim.run
      network_model = NetworkModel.new(events)

      open(File.join(dirname, 'network'), 'w'){|f|Marshal.dump(network_model,f)}
      open(File.join(dirname, 'traffic'), 'w'){|f|Marshal.dump(traffic_model,f)}
      if sel = spec.selected
        open(File.join(dirname, 'variant'), 'w'){|f| YAML.dump(sel,f)}
      end

      dirname
    end

    def self.analyzeBySpec(spec, base_dir)
      spec_obj = Specification.loadSpec(spec).new
      dirname  = File.join(base_dir, spec + '*')

      variants = Dir.glob(dirname).map do |dir|
	networkfile = File.join(dir, 'network')
	trafficfile = File.join(dir, 'traffic')
	variantfile = File.join(dir, 'variant')

	next unless File.exist?(networkfile) and File.exist?(trafficfile) and File.exist? variantfile

	puts "Opening stats for from #{dir}"

	variant = open(variantfile) {|f| YAML.load(f)}
	network = open(networkfile) {|f| Marshal.load(f)}
	traffic = open(trafficfile) {|f| Marshal.load(f)}

	[variant, network, traffic]
      end

      Analysis.new(variants, :experiment=>File.basename(base_dir)) do |analysis|
	spec_obj.analyze(analysis)
      end
    end

  end

end # module sim

if $0 == __FILE__
  ARGV.each {|spec| Sim::Core.runBySpec(spec)}
end

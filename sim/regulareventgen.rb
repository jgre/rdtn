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

$:.unshift File.join(File.dirname(__FILE__), "..", "lib")

require 'conf'
require 'rdtnevent'
require 'eventqueue'

module Sim

  class RegularEventConnection

    attr_reader :nodeId1, :nodeId2

    def initialize(id, connected)
      @nodeId1 = id
      @nodeId2 = id + 1
      @connected = connected
    end

    def nextEvent
      @connected = (not @connected)
      ret = if @connected then :simConnection
	    else               :simDisconnection
	    end
    end

  end

  class RegularEventGenerator

    def initialize(config, evDis, options)
      @config = config
      @interval = 10
      @interval = options[:interval] if options.has_key?(:interval)
      @eventdumpFile = options[:eventdump] if options.has_key?(:eventdump)
      if @eventdumpFile and File.exist?(@eventdumpFile)
	open(@eventdumpFile) {|f| @events = Marshal.load(f) }
      else
	@events    = EventQueue.new
	preprocess
      end
      @events.register(@config, evDis)

    end

    private

    def preprocess
      @connections = []
      1.upto(@config.nnodes - 1) do |n|
	if n % 2 == 0 then connected = true
	else               connected = false
	end
	@connections.push(RegularEventConnection.new(n, connected))
      end
      timer = 0.0
      while timer < @config.duration
	if timer.to_i % @interval == 0
	  @connections.each do |conn|
	    event = conn.nextEvent
	    if event == :simConnection
	      @events.addEvent(timer + 5, conn.nodeId1, conn.nodeId2, event)
	    else
	      @events.addEvent(timer, conn.nodeId1, conn.nodeId2, event)
	    end
	  end
	end
	timer += @config.granularity
      end
      @events.events = @events.events.sort_by {|ev| ev[0]}
      open(@eventdumpFile, 'w') {|f| Marshal.dump(@events, f)} if @eventdumpFile
    end

  end
end

Sim::TraceParserReg.instance.reg(:regularEventGenerator, Sim::RegularEventGenerator)

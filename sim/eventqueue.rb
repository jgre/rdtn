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

require 'rdtnevent'

module Sim

  class EventQueue

    attr_accessor :events, :deltaTime

    Struct.new("SimEvent", :time, :nodeId1, :nodeId2, :type)

    def initialize(time0 = 0)
      @events = [] # [time, nodeId1, nodeId2, :simConnection|:simDisconnection]
      @time0  = 0  # All event before time0 will be ignored
    end

    def register(evDis)
      @evTick = evDis.subscribe(:simTimerTick) do |t| 
	while @events[0] and @events[0].time <= t.to_f
	  nextEvent(evDis)
	end
      end
    end

    def nextEvent(evDis)
      return nil if @events.empty?
      ev = @events.shift
      #don't dispatch all events in the past when the timer is started
      #with an offset
      if ev.time >= @time0
	rdebug(self, "Dispatching #{ev}")
	if ev.nodeId1 and ev.nodeId2
	  evDis.dispatch(ev.type, ev.nodeId1, ev.nodeId2)
	else
	  evDis.dispatch(ev.type, ev.time)
	end
      end
      ev.time
    end

    def stop(evDis)
      evDis.unsubscribe(:simTimerTick, @evTick) if @evTick
    end

    def addEvent(time, nodeId1, nodeId2, type)
      @events.push(Struct::SimEvent.new(time, nodeId1, nodeId2, type))
      #@events.push([time, nodeId1, nodeId2, type])
      self
    end

    def addEventSorted(time, nodeId1, nodeId2, type)
      @events.each_with_index do |event, index|
	if event.time > time
	  @events.insert(index, 
			 Struct::SimEvent.new(time, nodeId1, nodeId2, type))
	  return self
	end
      end
      addEvent(time, nodeId1, nodeId2, type) # only when we could not find a 
                                             # place for the event
      self
    end

    def empty?
      @events.empty?
    end

    def sort
      @events = @events.sort_by {|ev| ev.time}
      self
    end

    def marshal_dump
      [@events, @time0]
    end

    def marshal_load(lst)
      @events = lst[0]
      @time0  = lst[1]
    end

    def to_yaml_properties
      %w{ @events @time0 }
    end

  end

end # module

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

  class Event
    attr_accessor :time, :nodeId1, :nodeId2, :type

    def initialize(time, nodeId1, nodeId2, type)
      @time    = time
      @nodeId1 = nodeId1
      @nodeId2 = nodeId2
      @type    = type
    end

    def dispatch(evDis)
      if @nodeId1 and @nodeId2
        evDis.dispatch(@type, @nodeId1, @nodeId2)
      else
        evDis.dispatch(@type, @time)
      end
    end

  end

  class EventQueue

    attr_accessor :events
    include Enumerable

    def initialize(time0 = 0)
      @events = [] # [time, nodeId1, nodeId2, :simConnection|:simDisconnection]
      @time0  = 0  # All event before time0 will be ignored
      @cur_ev = 0  # The index of the current event
    end

    def each(&blk)
      @events.each(&blk)
      self
    end

    def addEvent(time, nodeId1, nodeId2, type)
      @events.push(Event.new(time, nodeId1, nodeId2, type))
      self
    end

    def addEventSorted(time, nodeId1, nodeId2, type)
      @events.each_with_index do |event, index|
	if event.time > time
	  @events.insert(index, Event.new(time, nodeId1, nodeId2, type))
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

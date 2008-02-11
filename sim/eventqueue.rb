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

module Sim

  class EventQueue

    attr_accessor :events, :deltaTime

    def initialize(deltaTime = 0)
      @events = [] # [time, nodeId1, nodeId2, :simConnection|:simDisconnection]
      @deltaTime = deltaTime
    end

    def register(config, evDis)
      @eq = EventQueue.new
      evDis.subscribe(:simTimerTick) do |t| 
	# Set the offset to the fist clock tick, so that we start with time = 0
	# for the parser
	@offset = t.to_f unless @offset
	while @events[0] and @events[0][0] <= (t.to_f - @offset)
	  ev = @events.shift
	  evDis.dispatch(ev[3], ev[1], ev[2])
	end
      end
    end

    def addEvent(time, nodeId1, nodeId2, type)
      @events.push([time, nodeId1, nodeId2, type])
    end

    def empty?
      @events.empty?
    end

  end

end # module

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

module Sim

  class TimerEngine

    attr_reader :timer

    def initialize(evDis)
      @evDis = evDis
      @timer = 0
    end

    def run(eventQueue)
      @t0    = Time.now
      #while event = eventQueue.events.shift
      eventQueue.each do |event|
        @timer = event.time
        event.dispatch(@evDis)
      end
    end

    def time
      @t0 + @timer
    end

  end

end # module

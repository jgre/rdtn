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

require 'remconf'

module Rem

  class TimerEngine

    def initialize
    end

    def run
      timer = Time.now
      gran = Config.instance.granularity
      puts "Gran #{gran}"
      thresh = 0.01 # Tolerance for timing inaccuracy for realtime emulation
      loop do
	# Blocks until all work for this clock tick is done
	EventDispatcher.instance.dispatch(:remTimerTick, timer)
	if Config.instance.realTime
	  sleepTime =  (timer + gran) - Time.now
	  sleep(sleepTime) if sleepTime > 0
	  newTime = Time.now
	  if newTime > (timer + gran + thresh)
	    puts "Timing deviation too great: T-1 = #{timer.to_f}, T = #{newTime.to_f}"
	  end
	  timer = newTime
	else
	  timer += gran
	end
      end
    end
  end

end # module

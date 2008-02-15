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

    def initialize(config, evDis)
      @config = config
      @evDis  = evDis
    end

    def run(duration, startTime = 0)
      @t0 = Time.now - startTime
      @timer = startTime
      gran = @config["granularity"]
      thresh = 0.01 # Tolerance for timing inaccuracy for realtime emulation
      startTime.step(duration, gran) do |time|
	@timer = time
        @evDis.dispatch(:simTimerTick, @timer)
      end
      #loop do
      #  break if duration and @timer > duration
      #  # Blocks until all work for this clock tick is done
      #  @evDis.dispatch(:simTimerTick, @timer)
      #  if @config["realTime"]
      #    sleepTime =  (@timer + gran) - Time.now
      #    sleep(sleepTime) if sleepTime > 0
      #    newTime = Time.now
      #    if newTime > (@timer + gran + thresh)
      #      puts "Timing deviation too great: T-1 = #{timer.to_f}, T = #{newTime.to_f}"
      #    end
      #    @timer = newTime
      #  else
      #    puts "Time #{@timer} #{gran}"
      #    @timer += gran
      #  end
      #end
    end

    def time
      @t0 + @timer
    end

  end

end # module

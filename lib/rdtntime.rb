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

class RdtnTime

  @@timerFunc = lambda {Time.now}
  @@sleepFunc = lambda {|sec| sleep(sec)}
  @@scheduleFunc = lambda {|sec, handler|} # FIXME default for non-sim RDTN

  def RdtnTime.timerFunc=(func)
    @@timerFunc = func
  end

  def RdtnTime.timerFunc
    @@timerFunc
  end

  def RdtnTime.now
    @@timerFunc.call
  end

  def RdtnTime.sleepFunc=(func)
    @@sleepFunc = func
  end

  def RdtnTime.sleepFunc
    @@sleepFunc
  end

  def RdtnTime.rsleep(sec = nil)
    @@sleepFunc.call(sec)
  end

  def RdtnTime.scheduleFunc=(func)
    @@scheduleFunc = func
  end

  def RdtnTime.schedule(sec, &handler)
    @@scheduleFunc.call(sec, &handler)
  end

end

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
#
# $Id$

require "monitor"

class RdtnStringIO < StringIO
  include MonitorMixin

  def initialize(*args)
    mon_initialize
    super
  end

  def enqueue(data)
    synchronize do
      oldPos = self.pos
      # Append always at the end
      self.seek(0, IO::SEEK_END)
      self << data

      self.pos = oldPos
    end
  end

  def read(*args)
    synchronize do
      super
    end
  end
end

#class Queue < String
#  # Remove the first n_bytes bytes from the queue. Called by the parser states
#  # when the data has been processed.
#
#  def consume!(n_bytes)
#    self.slice!(0,n_bytes)
#  end
#
#end

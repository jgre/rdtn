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

module Bundling

  class ForwardLog

    Struct.new("ForwardLogEntry", :action, :status, :neighbor, :link, :time)

    def initialize
      @logEntries = []
      # :action can be one of :incoming, :replicate, :forward
      # :status is :infligh, :transmitted, :transmissionError,
      # :transmissionPending
    end

    def addEntry(action, status, neighbor, link = nil, time = RdtnTime.now)
      @logEntries.push(Struct::ForwardLogEntry.new(action, status, neighbor, 
						   link, time))
    end

    def getLatestEntry
      @logEntries[-1]
    end

  end

end # module

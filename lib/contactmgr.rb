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

require "rdtnevent"
require "cl"
require "eidscheme"
require "monitor"

class ContactManager < Monitor
  # The housekeeping timer determines the interval between checks for idle
  # links.
  def initialize(housekeepingTimer = 300)
    super()
    @log = RdtnConfig::Settings.instance.getLogger(self.class.name)
    # This list contains all links that are open. We need this list to be able
    # to close them on shutdown. Here we also have those links that are not in
    # contacts because the peer's EID could not (yet) be determined.
    @links = []

    EventDispatcher.instance().subscribe(:linkCreated) do |*args| 
      linkCreated(*args)
    end
    EventDispatcher.instance().subscribe(:linkClosed) do |*args|
      contactClosed(*args)
    end

    housekeeping(housekeepingTimer)
  end

  def findLinkByName(name)
    @links.each {|lnk| puts lnk}
    findLink { |lnk| lnk.name and lnk.name == name }
  end

  def findLink(&block)
    synchronize do
      return @links.find(&block)
    end
  end

  private
 
  def linkCreated(link)
    @log.debug("Link created #{link.name}")
    synchronize do
      @links << link
    end
  end

  def contactClosed(link)
    EventDispatcher.instance.dispatch(:routeLost, link)
    @log.debug(
	"Removing link #{link.object_id} from ContactManager")
    synchronize do
      @links.delete(link)
    end
  end

  # Housekeeping starts a thread that wakes up every +timer+ seconds and deletes
  # all opportunistic links from +@links+ that are not busy.
  
  def housekeeping(timer)
    Thread.new(timer) do |ti|
      while true
	sleep(timer)
	synchronize do
	  @links.delete_if {|lnk| lnk.policy != :alwaysOn and not lnk.busy?}
	end
      end
    end
  end

end

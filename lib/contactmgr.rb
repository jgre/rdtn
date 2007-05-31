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

require "rdtnevent"
require "cl"
require "eidscheme"
require "singleton"

class ContactManager
  def initialize
    # This hash contains the established contacts indexed by their EID
    @contacts = {}
    # This list contains all links that are open. We need this list to be able
    # to close them on shutdown. Here we also have those links that are not in
    # contacts because the peer's EID could not (yet) be determined.
    @links = []

    EventDispatcher.instance().subscribe(:linkCreated) do |*args| 
      self.linkCreated(*args)
    end
    EventDispatcher.instance().subscribe(:contactClosed) do |*args|
      self.contactClosed(*args)
    end
  end

  include Singleton

  def linkCreated(link)
    RdtnLogger.instance.debug("Link created #{link.name}")
    @links << link
  end

  def contactClosed(link)
    RdtnLogger.instance.debug("Removing link #{link.object_id} from ContactManager")
    @links.delete(link)
    if defined?(link.remoteEid) and link.remoteEid 
      @contacts.delete(link.remoteEid.indexingPart)
    end
  end

  def findLinkByEid(eid)
    eid = EID.new(eid) if eid.class != EID
    return @contacts[eid.indexingPart]
  end

  def findLink(&block)
    return @links.find(&block)
  end
end

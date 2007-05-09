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

require "bundle"
require "rdtnevent"
require "rdtnlog"
require "contactmgr"

class Router
  def initialize(contactManager)
    @contactManager = contactManager
    EventDispatcher.instance.subscribe(:bundleParsed) do |bundle|
      link = self.lookup(bundle.destEid)
      if link
	RdtnLogger.instance.debug("Forwarding bundle to #{bundle.destEid} on link #{link.object_id}")
	self.forward(bundle, link)
      else
	RdtnLogger.instance.debug("Could not find a link to forward bundle to #{bundle.dest_eid} on")
      end
    end
  end

  def lookup(eid)
    return @contactManager.findLinkByEid(eid)
  end

  def forward(bundle, link)
    link.sendBundle(bundle)
  end
end

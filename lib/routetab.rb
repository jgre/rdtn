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
require "storage"
require "contactmgr"
require "monitor"
require "router"

class RoutingTable < Router

  include MonitorMixin

  def initialize(config, evDis, options = {})
    super
    mon_initialize
    @routes         = []
    @contactManager = @config.contactManager

    @evAvailable = @evDis.subscribe(:routeAvailable) do |*args|
      self.addEntry(*args)
    end
    @evLost = @evDis.subscribe(:routeLost) do |*args|
      deleteEntry(*args)
    end
    @evToForward = @evDis.subscribe(:bundleToForward) do |*args|
      forward(*args)
    end
    @evError = @evDis.subscribe(:transmissionError) do |bundle, link|
      forward(bundle)
    end
  end

  def stop
    super
    @evDis.unsubscribe(:routeAvailable, @evAvailable)
    @evDis.unsubscribe(:routeLost, @evLost)
    @evDis.unsubscribe(:bundleToForward, @evToForward)
  end

  def print
    @routes.each do |entry|
      puts "#{entry.destination}\t#{entry.link}\t#{entry.exclusive}"
    end
  end

  def addEntry(routingEntry)
    rinfo("Added route to #{routingEntry.destination} over #{routingEntry.link}.")
    synchronize { @routes.push(routingEntry) }

    # See if we can send stored bundles over this link.
    store = @config.store
    if store
      bundles = store.getBundlesMatchingDest(routingEntry.destination)
      bulkEnqueue(bundles, routingEntry.link)
    end
  end

  def addRoute(dest, link)
    addEntry(RoutingEntry.new(dest, link))
  end

  def deleteEntry(link, dest = nil)
    synchronize do
      @routes.delete_if do |entry|
	if entry.link(@contactManager).to_s == link.to_s and (not dest or dest.to_s == entry.destination)
	  true
	else
	  false
	end
      end
    end
  end

  def match(dest)
    synchronize {@routes.find_all {|entry| entry.match?(dest)} }
  end

  def forward(bundle)
    rdebug("Forward: #{bundle.destEid}, #{bundle.srcEid}")
    matches = self.match(bundle.destEid.to_s)

    exclusiveLink = matches.find {|entry| entry.exclusive}
    matches = [exclusiveLink] if exclusiveLink
    matches.each {|entry| enqueue(bundle, entry.link(@contactManager))}
    nil
  end

end

regRouter(:routingTable, RoutingTable)

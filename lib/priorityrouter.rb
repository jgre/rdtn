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
require "clientregcl"
require "singleton"

# Priorities for epidemic routing. This means that priorities are randomly
# assigned.

class EpidemicPriorities

  def orderBundles(b1, b2, neighbor = nil)
    # Sort by generating a random value vor less than (-1), equal (0), or
    # grater than (1).
    rand(3) - 1
  end

end

class PriorityRouterQueue < Router

  include MonitorMixin

  attr_accessor :link

  def initialize(contactManager, neighbor, filters, priorities)
    mon_initialize
    @contactMgr = contactManager
    @neighbor   = neighbor.eid.to_s if neighbor
    @store      = RdtnConfig::Settings.instance.store
    #@prioAlg    = RdtnConfig::Settings.instance.prioAlg
    @filters    = filters
    @priorities = priorities
    @curIndex   = 0

    #@evLink = EventDispatcher.instance.subscribe(:linkClosed) do |l|
    #  unsubscribeEvents if l == @link
    #end
    # Avoid returning the bundle directly to its previous hop.
    @bundles = @store.find_all do |bundle|
      if not bundle then false
      elsif bundle.incomingLink and bundle.incomingLink.remoteEid and @neighbor
	if bundle.incomingLink.remoteEid.to_s == @neighbor then false
	else true
	end
      else true
      end
    end
    @evBundle = EventDispatcher.instance.subscribe(:bundleToForward) do |*args|
      addBundle(*args)
    end

  end

  def updateList
    @bundles.delete_if do |bundle|
      @filters.any? {|filter| filter.filterBundle?(bundle, @neighbor)}
    end
    @bundles.sort! do |b1, b2|
      # Accumulate the comparision from all priority algorithms to priorize
      # based on a bundle to bundle comparison.
      accPrio = @priorities.inject(0) do |sum, prio| 
	sum+prio.orderBundles(b1,b2, @neighbor)
      end
      if accPrio == 0   then 0
      elsif accPrio > 0 then 1
      else               -1
      end
    end
  end

  def forwardBundles
    return nil unless @link
    synchronize { updateList }
    #@bundles.delete_if {|bundle| @prioAlg.filterBundle?(@bundle, @neighbor) }
    #@bundles.sort! {|b1, b2| @prioAlg.orderBundles(@bundles, @neighbor) }
    until @curIndex >= @bundles.length
      bundle = synchronize do
	@curIndex += 1
        @bundles[@curIndex - 1]
      end
      doForward(bundle, [@link]) if bundle
    end
  end

  def addBundle(bundle)
    return nil if @bundles.find {|b| b.bundleId == bundle.bundleId}
    #puts "Neighbor #{@neighbor}"
    #puts "AddBundle #{bundle.incomingLink}"
    #puts "AddBundle #{bundle.incomingLink.remoteEid}" if bundle.incomingLink
    if bundle.incomingLink and bundle.incomingLink.remoteEid and @neighbor
      if bundle.incomingLink.remoteEid.to_s == @neighbor then return nil end
    elsif bundle.incomingLink == @link then return nil
    end
    #puts "Ok go ahead."
    wasEmpty = false
    synchronize do
      wasEmpty = @curIndex >= @bundles.length
      @bundles.push(bundle)
      #updateList
      #@bundles.delete_if {|bundle| @prioAlg.filterBundle?(@bundle, @neighbor) }
      #@bundles.sort! {|b1, b2| @prioAlg.orderBundles(@bundles, @neighbor) }
    end
    forwardBundles if wasEmpty
  end

  private

  def unsubscribeEvents
    EventDispatcher.instance.unsubscribe(:bundleToForward, @evBundle)
    EventDispatcher.instance.unsubscribe(:linkClosed, @evLink)
  end

end

class PriorityRouter < Router

  include MonitorMixin

  attr_accessor :filters, :priorities

  def initialize(contactManager, subHandler = nil)
    mon_initialize
    @contactManager = contactManager
    @filters    = []
    @priorities = []
    @routes     = []
    @subHandler = subHandler
    @queues = Hash.new {|h,n| h[n] = PriorityRouterQueue.new(@contactManager, n,
							@filters, @priorities)}

    EventDispatcher.instance.subscribe(:neighborContact) do |neighbor, link|
      contact(neighbor, link)
    end
    EventDispatcher.instance.subscribe(:routeAvailable) do |*args|
      localRegistration(*args)
    end
    EventDispatcher.instance.subscribe(:bundleToForward) do |*args|
      forward(*args)
    end
  end

  def contact(neighbor, link)
    if @subHandler
      EventDispatcher.instance.subscribe(:subscriptionsReceived) do |neighborEid|
	#puts "SubRec #{neighborEid}, #{neighbor.eid}"
	if neighborEid.to_s == neighbor.eid.to_s
          #puts "ProcQ"
	  processQueue(neighbor, link)
	end
      end
      doForward(@subHandler.generateSubscriptionBundle, [link])
    else
      processQueue(neighbor, link)
    end
  end

  def processQueue(neighbor, link)
    @queues[neighbor].link = link 
    @queues[neighbor].forwardBundles
  end

  def localRegistration(rentry)
    # We only care for client intrefaces
    return nil unless rentry.link.kind_of? AppIF::AppProxy

    synchronize { @routes.push(rentry) }

    # See if we can send stored bundles over this link.
    store = RdtnConfig::Settings.instance.store
    if store
      bundles = store.getBundlesMatchingDest(rentry.destination)
      bundles.each {|bundle| doForward(bundle, [rentry.link])}
    end
  end

  def forward(bundle)
    matches=synchronize do 
      @routes.find_all{|entry| entry.destination === bundle.destEid.to_s}
    end
    links = matches.map {|entry| entry.link(@contactManager)}
    doForward(bundle, links)
  end

  def addPriority(prio)
    @priorities.push(prio)
  end

  def addFilter(filter)
    @filters.push(filter)
  end

end

class PrioReg

  include Singleton

  attr_accessor :prios, :filters

  def initialize
    @prios = {}
    @filters = {}
  end

  def regPrio(name, klass)
    @prios[name] = klass
  end

  def regFilter(name, klass)
    @filters[name] = klass
  end

  def makePrio(name)
    @prios[name].new
  end

  def makeFilter(name)
    @filters[name].new
  end

end

def regPrio(name, klass)
  PrioReg.instance.regPrio(name, klass)
end

def regFilter(name, klass)
  PrioReg.instance.regFilter(name, klass)
end

regPrio(:epidemicPriorities, EpidemicPriorities)


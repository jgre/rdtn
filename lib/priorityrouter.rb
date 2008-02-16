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

class BogusPrio

  def initialize(config, evDis, subHandler)
  end

  def orderBundles(b1, b2, neighbor = nil)
    return 0
  end

end

class CopyCountFilter

  def initialize(config, evDis, subHandler)
  end

  def filterBundle?(bundle, neighbor = nil)
    bundle.forwardLog.nCopies > 3
  end

end

class PriorityRouterQueue < Router

  include MonitorMixin

  attr_accessor :link

  def initialize(config, evDis, contactManager, neighbor, filters, priorities)
    rdebug(self, "Starting new PriorityRouterQueue for #{neighbor}")
    mon_initialize
    super(evDis)
    @config     = config
    @contactMgr = contactManager
    @neighbor   = neighbor
    @store      = @config.store
    @filters    = filters
    @priorities = priorities

    @evLink = @evDis.subscribe(:linkClosed) do |l|
      if l == @link
	synchronize do
	  @link = nil
	  @curIndex = 0
	  unsubscribeEvents
	end
      end
    end
    @bundles = @store.to_a
    @evBundle = @evDis.subscribe(:bundleToForward) do |*args|
      addBundle(*args)
    end
  end

  def updateList
    synchronize do
      accepted = @bundles.reject do |bundle|
	@filters.any? do |filter| 
	  res = filter.filterBundle?(bundle, @neighbor)
	  if res and filter.class != SubscribeBundleFilter
	    rdebug(self, "#{filter.class} removed bundle #{bundle.srcEid} -> #{bundle.destEid}")
	  end
	  res
	end
      end
      @bundles = accepted.sort do |b1, b2|
	# Accumulate the comparision from all priority algorithms to priorize
	# based on a bundle to bundle comparison.
	accPrio = @priorities.inject(0) do |sum, prio| 
	  sum+prio.orderBundles(b1,b2, @neighbor)
	end
	if accPrio == 0   then 0
	elsif accPrio > 0 then 1
	else                  -1
	end
      end
    end
  end

  def forwardBundles
    return nil unless @link
    updateList
    until @bundles.empty?
      synchronize do
	bundle = @bundles.pop
	rdebug(self, "PrioRouter: forwarding #{bundle.bundleId}: #{bundle.srcEid} -> #{bundle.destEid}")
	doForward(bundle, [@link], :replicate) if bundle
      end
    end
  end

  def addBundle(bundle)
    synchronize do
      unless @bundles.find {|b| b.bundleId == bundle.bundleId}
	@bundles.push(bundle)
      end
    end
    forwardBundles
  end

  def unsubscribeEvents
    @evDis.unsubscribe(:bundleToForward, @evBundle)
    @evDis.unsubscribe(:linkClosed, @evLink)
  end

end

class PriorityRouter < Router

  include MonitorMixin

  attr_accessor :filters, :priorities

  def initialize(config, evDis)
    mon_initialize
    super(evDis)
    @config = config
    @contactManager = @config.contactManager
    @filters    = []
    @priorities = []
    @routes     = []
    @subHandler = @config.subscriptionHandler
    @queues = Hash.new {|h,n| h[n] = PriorityRouterQueue.new(@config, @evDis,
							     @contactManager, n,
							     @filters, 
							     @priorities)}

    @evContact = @evDis.subscribe(:neighborContact) do |neighbor, link|
      contact(neighbor, link)
    end
    @evAvailable = @evDis.subscribe(:routeAvailable) do |*args|
      localRegistration(*args)
    end
    @evToForward = @evDis.subscribe(:bundleToForward) do |*args|
      forward(*args)
    end
    @evLinkClosed = @evDis.subscribe(:linkClosed) do |l|
      @queues.delete(l.remoteEid)
    end
    if @subHandler
      @evSubRec = @evDis.subscribe(:subscriptionsReceived) do |neighborEid|
	neighbor = @contactManager.findNeighborByEid(neighborEid)
	if neighbor
	  link = neighbor.curLink 
	  #puts "SubRec #{neighborEid}, #{neighbor.eid}"
	  if link
	    #puts "(#{@config.localEid}) ProcQ1"
	    processQueue(neighbor, link)
	  else
	    puts "(#{@config.localEid}) Could not find link to #{neighborEid}"
	  end
	else
	  puts "(#{@config.localEid}) Could not find neighbor for #{neighborEid}"
	end
      end
    end
  end

  def stop
    @evDis.unsubscribe(:neighborContact, @evContact)
    @evDis.unsubscribe(:routeAvailable, @evAvailable)
    @evDis.unsubscribe(:bundleToForward, @evToForward)
    @evDis.unsubscribe(:linkClosed, @evLinkClosed)
    @evDis.unsubscribe(:subscriptionsReceived, @evSubRec)
    @queues.values.each {|q| q.unsubscribeEvents}
  end

  def contact(neighbor, link)
    if @subHandler
      doForward(@subHandler.generateSubscriptionBundle, [link])
    else
      processQueue(neighbor, link)
    end
  end

  def processQueue(neighbor, link)
    #puts "(#{@config.localEid}) Setting link #{link} at #{RdtnTime.now.to_i}"
    @queues[neighbor.eid.to_s].link = link 
    @queues[neighbor.eid.to_s].forwardBundles
  end

  def localRegistration(rentry)
    # We only care for client intrefaces
    return nil unless rentry.link.kind_of? AppIF::AppProxy

    synchronize { @routes.push(rentry) }

    # See if we can send stored bundles over this link.
    store = @config.store
    if store
      bundles = store.getBundlesMatchingDest(rentry.destination)
      bundles.each {|bundle| doForward(bundle, [rentry.link], :replicate)}
    end
  end

  def forward(bundle)
    matches=synchronize do 
      @routes.find_all{|entry| entry.destination === bundle.destEid.to_s}
    end
    links = matches.map {|entry| entry.link(@contactManager)}
    doForward(bundle, links, :replicate)
  end

  def addPriority(prio)
    if prio.class == Symbol
      prioAlg = PrioReg.instance.makePrio(prio, @config, @evDis,
					  @subscriptionHandler)
    else
      prioAlg = prio
    end
    @priorities.push(prioAlg)
  end

  def addFilter(filter)
    if filter.class == Symbol
      filterAlg = PrioReg.instance.makeFilter(filter, @config, @evDis, 
					      @settings.subscriptionHandler)
    else
      filterAlg = filter
    end
    @filters.push(filterAlg)
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

  def makePrio(name, config, evDis, subHandler)
    @prios[name].new(config, evDis, subHandler)
  end

  def makeFilter(name, config, evDis, subHandler)
    @filters[name].new(config, evDis, subHandler)
  end

end

def regPrio(name, klass)
  PrioReg.instance.regPrio(name, klass)
end

def regFilter(name, klass)
  PrioReg.instance.regFilter(name, klass)
end

regPrio(:epidemicPriorities, EpidemicPriorities)
regPrio(:bogus, BogusPrio)
regFilter(:copyCountFilter, CopyCountFilter)

regRouter(:priorityRouter, PriorityRouter)

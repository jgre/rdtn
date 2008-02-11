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
    bundle.nCopies > 3
  end

end

class PriorityRouterQueue < Router

  include MonitorMixin

  attr_accessor :link

  def initialize(config, evDis, contactManager, neighbor, filters, priorities)
    mon_initialize
    super(evDis)
    @config = config
    @contactMgr = contactManager
    @neighbor   = neighbor.eid.to_s if neighbor
    @store      = @config.store
    @filters    = filters
    @priorities = priorities
    @curIndex   = 0

    #if @config.localEid == "dtn://kasuari2/"
    #  @nbundlesAdded = 0
    #  @nbundlesActually = 0
    #end

    @evLink = @evDis.subscribe(:linkClosed) do |l|
      if l == @link
	synchronize do
	  @link = nil
	  @curIndex = 0
	end
	#puts "(#{@config.localEid}) Received Close #{l} at #{RdtnTime.now.to_i}"
      else
	#puts "(#{@config.localEid}) Close but not for me #{l}, #{@link}"
      end
    end
    # Avoid returning the bundle directly to its previous hop.
    @bundles = {}
    @store.each do |bundle|
      if bundle and not @bundles.has_key?(bundle.bundleId) and not /dtn:subscribe\/.*/ =~ bundle.destEid.to_s
	@bundles[bundle.bundleId] = bundle
      #elsif bundle.incomingLink and bundle.incomingLink.remoteEid and @neighbor
      #  if bundle.incomingLink.remoteEid.to_s == @neighbor then false
      #  else true
      #  end
      #else true
      end
    end
    @evBundle = @evDis.subscribe(:bundleToForward) do |*args|
      addBundle(*args)
    end
    @evDis.subscribe(:bundleForwarded) do |bndl, link|
      if @link and @link == link
	synchronize do
	  #@bundles.delete_if {|bundle| bundle.bundleId == bndl.bundleId}
	  @bundles[bndl.bundleId] = nil
	end
      end
    end
    @evDis.subscribe(:bundleRemoved) do |bndl|
      synchronize do
	@bundles[bndl.bundleId] = nil
	#@bundles.delete_if {|bundle| bundle.bundleId == bndl.bundleId}
      end
    end

  end

  def updateList
    #puts "(#{@config.localEid}) #{@bundles.length} Bundles in the queue"
    #@bundles.delete_if do |b| 
    #  RdtnTime.now.to_i > (b.creationTimestamp.to_i + b.lifetime.to_i + Time.gm(2000).to_i) 
    #end
    filtered, accepted = @bundles.values.compact.partition do |bundle|
      @filters.any? do |filter| 
	res = filter.filterBundle?(bundle, @neighbor)
	#puts "(#{@config.localEid}) #{filter.class} removed bundle #{bundle.srcEid} -> #{bundle.destEid}" if res and filter.class != SubscribeBundleFilter
	res
      end
    end
    accepted.sort! do |b1, b2|
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
    #@bundles  = filtered + accepted
    #@curIndex = filtered.length
    accepted
  end

  def forwardBundles
    synchronize do
      return nil unless @link
      bundles = updateList

      #@bundles.delete_if {|bundle| @prioAlg.filterBundle?(@bundle, @neighbor) }
      #@bundles.sort! {|b1, b2| @prioAlg.orderBundles(@bundles, @neighbor) }

      #until @curIndex >= bundles.length
      bundles.each do |bundle|
	#@curIndex += 1
	#bundle = @bundles[@curIndex - 1]
	break unless @link
	#puts "Forwarding over #{@link} at #{RdtnTime.now.to_i}"
	# FIXME Decrement this number when the bundle cannot be transmitted
	bundle.nCopies += 1
	doForward(bundle, [@link]) if bundle
      end
    end
  end

  def addBundle(bundle)
    #if @config.localEid == "dtn://kasuari1/" and bundle.destEid.to_s == "dtn://channel1/"
    #if @bundles.find {|b| b.bundleId == bundle.bundleId}
      #if @config.localEid == "dtn://kasuari2/" and @neighbor == "dtn://kasuari1/" and not bundle.destEid == "dtn:subscribe/"
      #  @nbundlesAdded += 1
      #  puts "(#{@config.localEid}) Removing bundle for #{bundle.destEid} because its already queued"
      ##puts "Adding bundle for #{bundle.destEid} (#{@nbundlesAdded})"
      #end
    #  return nil
    #end
    #puts "Neighbor #{@neighbor}"
    #puts "AddBundle #{bundle.incomingLink}"
    #puts "AddBundle #{bundle.incomingLink.remoteEid}" if bundle.incomingLink
    if bundle.incomingLink and bundle.incomingLink.remoteEid and @neighbor
      if bundle.incomingLink.remoteEid.to_s == @neighbor 
	#if @config.localEid == "dtn://kasuari2/" and @neighbor == "dtn://kasuari1/" and not bundle.destEid == "dtn:subscribe/"
	##if @config.localEid == "dtn://kasuari1/" and bundle.destEid.to_s == "dtn://channel1/"
	#  puts "Removing bundle because its from #{bundle.incomingLink.remoteEid}"
	#end
	return nil 
      end
    elsif @link and bundle.incomingLink == @link 
      #if @config.localEid == "dtn://kasuari2/" and @neighbor == "dtn://kasuari1/" and not bundle.destEid == "dtn:subscribe/"
      ##if @config.localEid == "dtn://kasuari2/" and @neighbor == "dtn://kasuari1/"
      #  puts "Removing bundle because came via #{bundle.incomingLink}"
      #end

      return nil
    end
    #if @config.localEid == "dtn://kasuari2/" and @neighbor == "dtn://kasuari1/" and not bundle.destEid == "dtn:subscribe/"
    ##if @config.localEid == "dtn://kasuari1/" and bundle.destEid.to_s == "dtn://channel1/"
    #  @nbundlesActually += 1
    #  #puts "Okay, this is really new #{@nbundlesActually}"
    #end
    #wasEmpty = false
    synchronize do
      #wasEmpty = @curIndex >= @bundles.length
      #if bundle and not @bundles.has_key?(bundle.bundleId)
      if bundle and not @bundles.has_key?(bundle.bundleId) and not /dtn:subscribe\/.*/ =~ bundle.destEid.to_s
	@bundles[bundle.bundleId] = bundle
      end
      #@bundles.push(bundle)
    end
    forwardBundles #if wasEmpty
  end

  private

  def unsubscribeEvents
    @evDis.unsubscribe(:bundleToForward, @evBundle)
    @evDis.unsubscribe(:linkClosed, @evLink)
  end

end

class PriorityRouter < Router

  include MonitorMixin

  attr_accessor :filters, :priorities

  def initialize(config, evDis, contactManager, subHandler = nil)
    mon_initialize
    super(evDis)
    @config = config
    @contactManager = contactManager
    @filters    = []
    @priorities = []
    @routes     = []
    @subHandler = subHandler
    @queues = Hash.new {|h,n| h[n] = PriorityRouterQueue.new(@config, @evDis,
							     @contactManager, n,
							     @filters, 
							     @priorities)}

    @evDis.subscribe(:neighborContact) do |neighbor, link|
      contact(neighbor, link)
    end
    @evDis.subscribe(:routeAvailable) do |*args|
      localRegistration(*args)
    end
    @evDis.subscribe(:bundleToForward) do |*args|
      forward(*args)
    end
    if @subHandler
      @evDis.subscribe(:subscriptionsReceived) do |neighborEid|
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

  def contact(neighbor, link)
    if @subHandler
      doForward(@subHandler.generateSubscriptionBundle, [link])
    else
      processQueue(neighbor, link)
    end
  end

  def processQueue(neighbor, link)
    #puts "(#{@config.localEid}) Setting link #{link} at #{RdtnTime.now.to_i}"
    @queues[neighbor].link = link 
    @queues[neighbor].forwardBundles
  end

  def localRegistration(rentry)
    # We only care for client intrefaces
    return nil unless rentry.link.kind_of? AppIF::AppProxy

    synchronize { @routes.push(rentry) }

    # See if we can send stored bundles over this link.
    store = @config.store
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


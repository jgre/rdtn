require 'router'
require 'bundle'
require 'rdtntime'
require 'subscriptionset'
require 'yaml'
require 'hopcountblock'

class DPSPRouter < Router

  attr_reader :subSet

  def initialize(config, evDis, options = {})
    super(config, evDis)
    @contMgr   = @config.contactManager
    subsRange  = options[:subsRange] || 1
    @subSet    = SubscriptionSet.new config, evDis, subsRange
    @neighbors = {}
    @prios     = options[:prios]   || []
    @filters   = options[:filters] || []
    @hopCountLimit = options[:hopCountLimit]

    RdtnTime.schedule(3600) do |time|
      @subSet.housekeeping!
      @neighbors.each_value {|subSet| subSet.housekeeping!}
      true
    end

    @evToForward = @evDis.subscribe(:bundleToForward) do |b|
      if b.isSubscriptionBundle?
	link = b.incomingLink
	@neighbors[link] = subset = YAML.load(b.payload)
	@subSet.import subset
	if link and store = @config.store and !link.is_a?(AppIF::AppProxy)
	  bulkEnqueue(store.to_a, link, :replicate)
	end
      else
	links = @contMgr.links.each do |l|
	  enqueue(b,l,:replicate) if (!l.is_a?(AppIF::AppProxy) && @neighbors[l])
	end
	
      end
    end

    @evAvailable = @evDis.subscribe(:routeAvailable) do |rentry|
      if rentry.link.is_a?(AppIF::AppProxy)
	@subSet.subscribe rentry.destination
      else
	enqueue(subscriptionBundle, rentry.link)
      end
    end

    #@evSubsRec = @evDis.subscribe(:subscriptionsReceived) do |neighbor|
    #  link = @contMgr.findLink {|lnk| lnk.remoteEid == neighbor}
    #  @neighbors[link] = true
    #  if link and store = @config.store and !link.is_a?(AppIF::AppProxy)
    #    store.each {|b| enqueue(b, [link], :replicate)}
    #  end
    #end

    @evClosed = @evDis.subscribe(:linkClosed) do |link|
      @neighbors.delete(link)
      @subSet.unsubscribe link.remoteEid if link.is_a?(AppIF::AppProxy)
    end
  end

  def stop
    super
    @evDis.unsubscribe(:routeAvailable, @evAvailable)
    @evDis.unsubscribe(:bundleToForward, @evToForward)
    @evDis.unsubscribe(:subscriptionsReceived, @evSubsRec)
    @evDis.unsubscribe(:linkClosed, @evClosed)
  end

  def subsRange=(range)
    @subSet.subsRange = range
  end

  SUBSCRIBE_EID = 'dtn:subscribe/'

  def subscriptionBundle
    dump = YAML.dump(@subSet)
    Bundling::Bundle.new dump, SUBSCRIBE_EID, @config.localEid
  end

  protected

  def compare(b1, b2, link)
    @prios.inject(0) {|memo, prio| memo + self.send(prio, b1, b2, link)}
  end

  def filter?(bundle, link)
    false or @filters.any? {|filter| self.send(filter, bundle, link)}
  end

  def enqueue(bundle, link, action = :forward)
    unless !bundle.isSubscriptionBundle? && filter?(bundle, link)
      idx = -1
      @queues[link].each_with_index do |entry, i|
	if compare(bundle, entry[0], link) < 0
	  idx = i
	  break
	end
      end
      @queues[link].insert(idx, [bundle, action])
      shiftQueue link
    end
    nil
  end

  def bulkEnqueue(bundles, link, action = :forward)
    @queues[link] += bundles.map {|b| [b, action]}
    @queues[link].sort! {|e1, e2| compare(e1[0], e2[0], link)}
    shiftQueue link
    nil
  end

  def knownSubscription?(bundle, link)
    !@subSet.subscribed?(bundle.destEid)
  end

  def exceedsHopCountLimit?(bundle, link)
    if @hopCountLimit && hc = bundle.findBlock(HopCountBlock)
      ret = hc.hopCount + 1 > @hopCountLimit
      ret
    end
  end

  def popularity(b1, b2, link)
    @subSet.subscribers(b2.destEid).length <=> @subSet.subscribers(b1.destEid).length
  end

  def hopCount(b1, b2, link)
    if (hc1 = b1.findBlock(HopCountBlock))&&(hc2 = b2.findBlock(HopCountBlock))
      hc1.hopCount <=> hc2.hopCount
    else
      0
    end
  end

end

regRouter(:dpsp, DPSPRouter)

module Bundling
  class Bundle
    def isSubscriptionBundle?
      destEid == DPSPRouter::SUBSCRIBE_EID
    end
  end
end

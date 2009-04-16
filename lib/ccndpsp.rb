require 'router'
require 'bundle'
require 'rdtntime'
require 'subscriptionset'
require 'yaml'
require 'hopcountblock'

class CCNDPSPRouter < Router

  attr_reader :subSet

  def initialize(config, evDis, options = {})
    super
    @contMgr   = @config.contactManager
    # @subsRange = options[:subsRange] || 1
    @prios     = options[:prios]   || []
    @filters   = options[:filters] || []
    @hopCountLimit = options[:hopCountLimit]
#     @neighbors = Hash.new do |h, k|
#       set      = SubscriptionSet.new config, evDis, @subsRange
#       set.node = k
#       h[k]     = set
#     end

    RdtnTime.schedule(3600) do |time|
      @subSet.housekeeping!
      # @neighbors.each_value {|subSet| subSet.housekeeping!}
      true
    end

    @evToForward = @evDis.subscribe(:bundleToForward) do |b|
#       if b.isSubscriptionBundle? && b.srcEid != @config.localEid
# 	link = @config.forwardLog[b.bundleId].incomingLink
# 	if @handshake
# 	  @neighbors[link.remoteEid] = subset = YAML.load(b.payload)
# 	  @subSet.import subset
# 	  enqueueFromStore(link)
# 	else
# 	  uri  = b.payload
# 	  if (hcblock = b.findBlock(HopCountBlock))
# 	    hc   = hcblock.hopCount
# 	    hc_1 = hc - 1
# 	  end
# 	  @neighbors[link.remoteEid].subscribe(uri, b.srcEid, :hopCount => hc_1,
# 				     :created => b.created,
# 				     :expires => b.expires)
# 	  @subSet.subscribe(uri, b.srcEid, :hopCount => hc,
# 			    :created => b.created,
# 			    :expires => b.expires)
# 	end
#      end
#       unless b.isSubscriptionBundle? && @handshake
      links = @contMgr.links.each do |l|
        unless @handshake && @neighbors[l.remoteEid].nil?
          enqueue(b, l, :replicate) if (!l.is_a?(AppIF::AppProxy))
        end
      end
#       end
    end

    @evAvailable = @evDis.subscribe(:routeAvailable) do |rentry|
      if rentry.link.is_a?(AppIF::AppProxy)

      else
        enqueueFromStore(rentry.link)
      end
    end

    @evClosed = @evDis.subscribe(:linkClosed) do |link|
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
    @subsRange = range
    @subSet.subsRange = range
  end

  SUBSCRIBE_EID = 'dtn:subscribe/'

  def subscriptionBundle(uri = nil)
    if @handshake
      dump = YAML.dump(@subSet)
      Bundling::Bundle.new dump, SUBSCRIBE_EID, @config.localEid
    else
      bundle = Bundling::Bundle.new(uri, SUBSCRIBE_EID, @config.localEid,
				    :lifetime  => @subSet.defaultExpiry,
				    :multicast => true)
      block  = HopCountBlock.new(bundle)
      bundle.addBlock(block)
      bundle
    end
  end

  protected

  def enqueueFromStore(link)
    if link and store = @config.store and !link.is_a?(AppIF::AppProxy)
      storedBundles = store.to_a
      storedBundles.delete_if(&:isSubscriptionBundle?) if @handshake
      bulkEnqueue(storedBundles, link, :replicate)
    end
  end

  def compare(b1, b2, link)
    @prios.inject(0) {|memo, prio| memo + self.send(prio, b1, b2, link)}
  end

  def subsRangeExceeded?(bundle, link)
    if bundle.isSubscriptionBundle? && (hcblock=bundle.findBlock(HopCountBlock))
      hcblock.hopCount > 1 # @subsRange
    end
  end

  def filter?(bundle, link)
    if bundle.isSubscriptionBundle?
      subsRangeExceeded?(bundle, link)
    else
      @filters.any? {|filter| self.send(filter, bundle, link)}
    end
  end

  def enqueue(bundle, link, action = :forward)
    #puts "(#{@config.localEid}, #{RdtnTime.now.sec}) enq #{bundle.inspect}"
    unless filter?(bundle, link)
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
    if ccn_blk = bundle.findBlock(CCNBlock) and ccn_blk.method == :publish
      !@subSet.subscribed?(ccn_blk.uri)
    end
  end

  def exceedsHopCountLimit?(bundle, link)
    if @hopCountLimit && hc = bundle.findBlock(HopCountBlock)
      ret = hc.hopCount + 1 > @hopCountLimit
      ret
    end
  end

  def popularity(b1, b2, link)
    if (ccn_blk1 = b1.findBlock(CCNBlock)) && (ccn_blk2=b2.findBlock(CCNBlock)) && ccn_blk1.method == :publish && ccn_blk2.method == :publish
      uri1 = ccn_blk1.uri
      uri2 = ccn_blk2.uri
      ret = @subSet.subscribers(uri1).length <=> @subSet.subscribers(uri2).length
      puts "(#{@config.localEid}, #{RdtnTime.now.sec}) popularity #{uri1} <=> #{uri2}: #{ret}"
      ret
    else
      0
    end
  end

  def hopCount(b1, b2, link)
    if (hc1 = b1.findBlock(HopCountBlock))&&(hc2 = b2.findBlock(HopCountBlock))
      hc1.hopCount <=> hc2.hopCount
    else
      0
    end
  end

  def shortDelay(b1, b2, link)
    b2.created.to_i <=> b1.created.to_i
  end

  def proximity(b1, b2, link)
    c1 = b1.destEid
    c2 = b2.destEid
    return 0 if [c1, c2].include? 'dtn:subscribe/'
    neighborSubs = @neighbors[link.remoteEid]
    return 0 if neighborSubs.nil?
    hc1 = neighborSubs.hopCounts(c1).values.min || Float::MAX
    hc2 = neighborSubs.hopCounts(c2).values.min || Float::MAX

    hc1 <=> hc2
  end

end

regRouter(:ccndpsp, CCNDPSPRouter)

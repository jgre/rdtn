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
require "clientlib"
require "eidscheme"
require "genparser"
require "queue"
require "clientregcl"
require "rdtntime"

class Subscription

  attr_accessor :uri,
    		:uniqueSubscriptions,
                :bundlesReceived,    # The bundles for this channel (URI) that 
				     # were already received.
		:nUSubs

  include GenParser

  field :uriLength, :decode => GenParser::SdnvDecoder
  field :uri,       :length => :uriLength
  field :nbundles,  :decode => GenParser::SdnvDecoder
  field :bundlesReceived, :decode => GenParser::NullTerminatedDecoder,
    :array => true, :length => :nbundles, :handler => :addBundleReceived
  field :nUSubs, :decode => GenParser::SdnvDecoder

  def initialize(config, evDis, uri)
    @config = config
    @evDis = evDis
    @uri = uri
    @uniqueSubscriptions = []
    @bundlesReceived = []
    @nUSubs = 0

    #@evDis.subscribe(:bundleToForward) do |bundle|
    #  if bundle.destEid.to_s == @uri.to_s
    #  puts "Bundle Received #{bundle.destEid}"
    #  addBundleReceived(bundle.bundleId) 
    #  end
    #end
  end

  def bundleReceived?(bundleId)
    #puts "BundlesReceived #{bundleId} #{bundleId.class}"
    #@bundlesReceived.each {|br| puts "#{br}, #{br.class}"}
    @bundlesReceived.include?(bundleId)
  end

  def copy
    ret = Subscription.new(@config, @evDis, @uri)
    ret.bundlesReceived = @bundlesReceived.clone
    @uniqueSubscriptions.each{|us| ret.uniqueSubscriptions.push(us.copy)}
    return ret
  end

  def merge(sub2)
    return nil if @uri != sub2.uri
    @bundlesReceived = sub2.bundlesReceived.clone
    sub2.uniqueSubscriptions.each do |us|
      myus = @uniqueSubscriptions.find {|u| u.uid == us.uid}
      if myus then myus.merge(us)
      else @uniqueSubscriptions.push(us.copy)
      end
    end
  end

  def ===(sub2)
    Regexp.new(@uri.to_s) === sub2.uri.to_s
  end

  def local?
    @uniqueSubscriptions.any? {|us| us.local}
  end

  def creationTimestamp(select = :min)
    tss = @uniqueSubscriptions.map {|us| us.creationTimestamp.to_i}
    case select
    when :min then return tss.min
    when :max then return tss.max
    when :average
      sum = tss.inject {|sum, ts| sum + ts}
      return sum / tss.length
    end
  end

  def expires(select = :max)
    tss = @uniqueSubscriptions.map {|us| us.expires.to_i}
    case select
    when :min then return tss.min
    when :max then return tss.max
    when :average
      sum = tss.inject {|sum, ts| sum + ts}
      return sum / tss.length
    end
  end

  def hopCount(select = :min)
    hcs = @uniqueSubscriptions.map {|us| us.hopCount}
    #puts "UniqueSubs empty!" if hcs.empty?
    case select
    when :min then return hcs.min
    when :max then return hcs.max
    when :average
      sum = hcs.inject {|sum, hc| sum + hc}
      return sum / hcs.length
    end
  end

  def timeOfArrival(select = :min)
    toas = @uniqueSubscriptions.map {|us| us.timeOfArrival}
    case select
    when :min then return toas.min
    when :max then return toas.max
    when :average
      sum = toas.inject {|sum, toa| sum + toa}
      return sum / toas.length
    end
  end

  def transitTime(select = :average)
    tts = @uniqueSubscriptions.map {|us| us.transitTime}
    case select
    when :min then return tts.min
    when :max then return tts.max
    when :average
      sum = tts.inject {|sum, tt| sum + tt}
      return sum / tts.length
    end
  end

  def Subscription.parse(config, evDis, io)
    ret = Subscription.new(config, evDis, "")
    ret.parse(io)
    ret.nUSubs.times do 
      usub = UniqueSubscription.parse(io)
      if usub.hopCount <= 2
	ret.uniqueSubscriptions.push(usub)
      #else
	#puts "Ignoring UniqueSubscription with hopcount #{usub.hopCount}"
      end
    end
    return nil if ret.uniqueSubscriptions.empty?
    return ret
  end

  def getBundlesReceived
    store = @config.store
    if store
      bundles = store.getBundlesMatchingDest(@uri.to_s, true) 
      @bundlesReceived.concat(bundles.map {|b| b.bundleId})
      @bundlesReceived.uniq!
    end
  end

  def serialize(io)
    getBundlesReceived
    io.write(Sdnv.encode(@uri.to_s.length))
    io.write(@uri)
    io.write(Sdnv.encode(@bundlesReceived.length))
    @bundlesReceived.each {|b| io.write(b.to_s + "\0")}
    io.write(Sdnv.encode(@uniqueSubscriptions.length))
    @uniqueSubscriptions.each {|us| us.serialize(io)}
  end

  def addBundleReceived(bundleRec)
    @bundlesReceived.push(bundleRec.to_i) unless @bundlesReceived.include?(bundleRec.to_i)
  end

end

class UniqueSubscription
  attr_accessor :link, :local, :timeOfArrival,
		:neighbors           # The subscribing neighbors

  include GenParser

  field :uriLength, :decode => GenParser::SdnvDecoder
  # Unique ID of the subscriptions we received (UIDs are generated by the 
  # original subscriber)
  field :uid,       :length => :uriLength
  # This is not the creation time of the bundle
  field :creationTimestamp, :decode => GenParser::SdnvDecoder
  field :expires,   :decode => GenParser::SdnvDecoder
  field :hopCount,  :decode => GenParser::SdnvDecoder

  def initialize(link, localEid, local = true,
		 creationTimestamp = RdtnTime.now,expires=RdtnTime.now+86400,
		 hopCount = 0)
    @link = link
    @localEid = localEid
    @local = local
    @uid = UniqueSubscription.generateUID
    @creationTimestamp = creationTimestamp
    @expires = expires
    @hopCount = hopCount
    @timeOfArrival = RdtnTime.now
    @neighbors = []
  end

  def UniqueSubscription.generateUID
    "#{@localEid.to_s}#{RdtnTime.now}#{rand}".hash.to_s
  end

  def UniqueSubscription.parse(io)
    ret = UniqueSubscription.new(nil, @localEid, false)
    ret.parse(io)
    return ret
  end

  def transitTime
    (@timeOfArrival - @creationTimestamp).to_i
  end

  def creationTimestamp=(ts)
    @creationTimestamp = (Time.gm(2000) + ts).to_i
  end

  def expires=(ts)
    @expires = (Time.gm(2000) + ts).to_i
  end

  def serialize(io)
    io.write(Sdnv.encode(@uid.to_s.length))
    io.write(@uid)
    io.write(Sdnv.encode(wireCreationTimestamp))
    io.write(Sdnv.encode(wireExpires))
    io.write(Sdnv.encode(hopCount))
  end

  def copy
    ret = UniqueSubscription.new(@link, @localEid, @local, @creationTimestamp, 
				 @expires, @hopCount + 1)
    ret.uid = @uid.clone if @uid
    ret.neighbors = @neighbors.clone if @neighbors
    return ret
  end

  def merge(sub2)
    return nil if @uid != sub2.uid or @local
    @expires = [@expires.to_i, sub2.expires.to_i].max
    @hopCount = [@hopCount, sub2.hopCount + 1].min
  end


  private

  def wireCreationTimestamp
    (@creationTimestamp - Time.gm(2000).to_i).to_i
  end

  def wireExpires
    (@expires - Time.gm(2000).to_i).to_i
  end

end

class SubscriptionList

  attr_accessor :subscriptions, :neighbor

  def initialize(contactMgr, neighbor = nil)
    @contactMgr    = contactMgr
    @neighbor      = neighbor
    @subscriptions = []
  end

  def addSubscription(subscription)
    if @subscriptions.grep(subscription).empty?
      @subscriptions.push(subscription)
      return true
    else
      return false
    end
  end

  def findSubscription(&handler)
    @subscriptions.find(&handler)
  end

  def findAllSubscriptions(&handler)
    @subscriptions.find_all(&handler)
  end

  def check
    @subscriptions.delete_if {|sub| sub.expires < RdtnTime.now}
  end

  def merge(subList2)
    subList2.subscriptions.each do |sub|
      mySub = findSubscription {|s| s.uri == sub.uri}
      if mySub then mySub.merge(sub)
      else @subscriptions.push(sub.copy)
      end
    end
  end

  def subscribedUris
    @subscriptions.map {|sub| sub.uri.to_s}
  end

  def subscribed?(uri)
    subscribedUris.include?(uri.to_s)
  end

  def bundlesReceived
    @subscriptions.inject([]) {|list, sub| list.concat(sub.bundlesReceived)}
  end

  def bundleReceived?(bundleId)
    @subscriptions.any? {|sub| sub.bundleReceived?(bundleId)}
  end

  def serialize(priorities = nil)
    io = RdtnStringIO.new
    if priorities
      # TODO priorize subscriptions for neighborEid
    end
    @subscriptions.each {|sub| sub.serialize(io)}
    io.rewind
    return io.read
  end

  def parse(config, evDis, io)
    while not io.eof?
      sub = Subscription.parse(config, evDis, io)
      addSubscription(sub) if sub
    end
  end

  def check
    @subscriptions.delete_if {|sub| sub.expires < RdtnTime.now.to_i}
  end

end

class SubscriptionHandler

  EidPattern = /dtn:subscribe\/.*/

  attr_reader :mySubs, :neighborSubs

  def initialize(config, evDis, contactManager, checkInterval = 300)
    @config = config
    @evDis = evDis
    @contactMgr = contactManager
    @evDis.subscribe(:bundleToForward) do |bundle|
      if EidPattern =~ bundle.destEid.to_s
	processBundle(bundle)
      end
    end
    @mySubs = SubscriptionList.new(@contactMgr, nil)
    @neighborSubs = {}
    @subClients = []
    @subscribeBundleId = nil
    @config.registerComponent(:subscriptionHandler, self)

    #@evDis.subscribe(:linkCreated){|link| sendSubscribe(link)}
    Thread.new(checkInterval) do |interval|
      Thread.current.abort_on_exception = true
      RdtnTime.rsleep(interval)
      check
    end

  end

  def subscribe(uri, subClient = nil, creationTimestamp = RdtnTime.now, 
		expires = RdtnTime.now + 86400, &handler)
    #subClient = RdtnClient.new(@client.host, @client.port) if not subClient
    #subClient.register(uri, &handler)
    #@subClients.push(subClient)
    sub = Subscription.new(@config, @evDis, uri)
    sub.uniqueSubscriptions.push(UniqueSubscription.new(nil, @config.localEid,
						       	true, 
							creationTimestamp, 
							expires))
    @mySubs.addSubscription(sub)
  end

  def subscribedUris
    @mySubs.subscribedUris
  end

  def subscribed?(uri)
    @mySubs.subscribed?(uri)
  end

  def generateSubscriptionBundle(neighborEid = nil)
    payload = @mySubs.serialize(nil) #TODO priority alg
    bundle = Bundling::Bundle.new(payload, "dtn:subscribe/", @config.localEid)
    @subscribeBundleId = bundle.bundleId
    return bundle
  end

  def processBundle(bundle)
    neighbor = bundle.srcEid.to_s
    unless @neighborSubs[neighbor]
      @neighborSubs[neighbor] = SubscriptionList.new(@contactMgr, neighbor)
    end
    io = RdtnStringIO.new(bundle.payload)
    @neighborSubs[neighbor.to_s].parse(@config, @evDis, io)
    @mySubs.merge(@neighborSubs[neighbor.to_s])
    @evDis.dispatch(:subscriptionsReceived, neighbor)
    store = @config.store
    store.deleteBundle(bundle.bundleId) if store

      #FIXME create subscription list for neighbor
      #sub.link = bundle.incomingLink
      #if sub.link and @contactMgr and sub.link.remoteEid
      #  sub.neighbors.push(@contactMgr.findNeighborByEid(sub.link.remoteEid))
      #end
  end

  private

  def check
    @mySubs.check
    @neighborSubs.each_value {|slist| slist.check}
  end

end

class SubscribeBundleFilter

  def initialize(config, evDis, subHandler)
  end

  def filterBundle?(bundle, neighbor = nil)
    if /dtn:subscribe\/.*/ =~ bundle.destEid.to_s
      return true
    else
      return false
    end
  end

end

regFilter(:subscribeBundleFilter, SubscribeBundleFilter)

class DuplicateFilter

  def initialize(config, evDis, subHandler)
    @subHandler = subHandler
  end

  def filterBundle?(bundle, neighbor = nil)
    return false unless neighbor and @subHandler.neighborSubs[neighbor.to_s]
    ret = @subHandler.neighborSubs[neighbor.to_s].bundleReceived?(bundle.bundleId)
    #puts "DuplicateFilter" if ret
    ret
  end

end

regFilter(:duplicateFilter, DuplicateFilter)

class KnownSubscriptionFilter

  def initialize(config, evDis, subHandler)
    @subHandler = subHandler
  end

  def filterBundle?(bundle, neighbor = nil)
    return false unless neighbor 
    return true  unless @subHandler.neighborSubs[neighbor.to_s]
    return (not @subHandler.neighborSubs[neighbor.to_s].subscribed?(bundle.destEid.to_s))
  end

end

regFilter(:knownSubscriptionFilter, KnownSubscriptionFilter)

class HopCountFilter

  def initialize(config, evDis, subHandler)
    @subHandler = subHandler
  end

  def filterBundle?(bundle, neighbor = nil)
    return false unless neighbor and @subHandler.neighborSubs[neighbor.to_s]
    slistN = @subHandler.neighborSubs[neighbor.to_s]
    slistM = @subHandler.mySubs
    nsub = slistN.findSubscription {|sub| sub.uri == bundle.destEid.to_s}
    mysub = slistM.findSubscription {|sub| sub.uri == bundle.destEid.to_s} 
    if nsub and mysub
      ret = nsub.hopCount > (mysub.hopCount)
      return ret
    else
      return false
    end
  end
end

regFilter(:hopCountFilter, HopCountFilter)

class BundleTimeFilter

  def initialize(config, evDis, subHandler)
    @subHandler = subHandler
  end

  def filterBundle?(bundle, neighbor = nil)
    slistM = @subHandler.mySubs
    mysub = slistM.findSubscription {|sub| sub.uri == bundle.destEid} 
    return false unless mysub
    expires = bundle.creationTimestamp + Time.gm(2000).to_i + bundle.lifetime
    return (RdtnTime.now + mysub.transitTime).to_i > expires.to_i
  end

end

regFilter(:bundleTimeFilter, BundleTimeFilter)

class SubscriptionHopCountPrio

  def initialize(config, evDis, subHandler)
    @subHandler = subHandler
  end

  def orderBundles(b1, b2, neighbor = nil)
    return 0 unless neighbor
    slistN = @subHandler.neighborSubs[neighbor.to_s]
    slistM = @subHandler.mySubs
    add1 = add2 = 0
    sub1 = sub2 = nil
    sub1 = slistN.findSubscription {|sub| sub.uri == b1.destEid} if slistN
    unless sub1
      sub1 = slistM.findSubscription {|sub| sub.uri == b1.destEid} 
      add1 = 1
    end
    sub2 = slistN.findSubscription {|sub| sub.uri == b2.destEid} if slistN
    unless sub2
      sub2 = slistM.findSubscription {|sub| sub.uri == b2.destEid}
      add2 = 1
    end

    if sub1 and sub2 
      #puts "#{sub1.hopCount}, #{sub2.hopCount}."
      return sub1.hopCount + add1 <=> sub2.hopCount + add2
    else
      return 0
    end
  end

end

regPrio(:subscriptionHopCount, SubscriptionHopCountPrio)

class PopularityPrio

  def initialize(config, evDis, subHandler)
    @subHandler = subHandler
  end

  def orderBundles(b1, b2, neighbor = nil)
    return 0 unless neighbor
    slist = @subHandler.mySubs
    sub1 = slist.findSubscription {|sub| sub.uri == b1.destEid} 
    sub2 = slist.findSubscription {|sub| sub.uri == b2.destEid} 
    nusubs1 = sub1 ? sub1.uniqueSubscriptions.length : 0
    nusubs2 = sub2 ? sub2.uniqueSubscriptions.length : 0
    return nusubs2 <=> nusubs1
  end
  
end

regPrio(:popularity, PopularityPrio)

class LongDelayPrio

  def initialize(config, evDis, subHandler)
  end

  def orderBundles(b1, b2, neighbor = nil)
    b1.creationTimestamp <=> b2.creationTimestamp
  end

end

regPrio(:longDelay, LongDelayPrio)

class ShortDelayPrio

  def initialize(config, evDis, subHandler)
  end

  def orderBundles(b1, b2, neighbor = nil)
    b2.creationTimestamp <=> b1.creationTimestamp
  end

end

regPrio(:shortDelay, ShortDelayPrio)

class BundleCopiesPrio

  def initialize(config, evDis, subHandler)
    @subHandler = subHandler
  end

  def orderBundles(b1, b2, neighbor = nil)
    # TODO
  end

end

regPrio(:bundleCopies, BundleCopiesPrio)

class FeedbackPrio

  def initialize(config, evDis, subHandler)
    @subHandler = subHandler
  end

  def orderBundles(b1, b2, neighbor = nil)
    # TODO
  end

end

regPrio(:feedback, FeedbackPrio)

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

class RoutingEntry
  attr_reader :destination,
    	      :exclusive

  def initialize(dest, link, exclusive = false)
    @destination = dest
    @link = link
    @exclusive = exclusive
  end

  # If +@link+ is not the Link object itself  but only its name lookup the name
  # in the +ContactManager+ and assign the Link object to +@link+.
  # Returns +@link+

  def link(contactManager = nil)
    if contactManager and not @link.kind_of?(Link)
      @link = contactManager.findLinkByName(link)
    end
    return @link
  end

  def match?(eid)
    Regexp.new(@destination) === eid
  end

end

class Router

  def initialize(config, evDis, options = {})
    @config   = config
    @evDis    = evDis
    @localReg = []
    @queues   = Hash.new {|h, k| h[k] = []}
    @config.registerComponent(:router, self) {self.stop}
    @subSet   = @config.subscriptionSet
    @cacheSubscriptions = options[:cacheSubscriptions]
    @pollInterval = options[:pollInterval]
    @bundleLifetime = options[:bundleLifetime] || 3600
    @pollSubscriptions = []

    @rtEvAvailable = @evDis.subscribe(:routeAvailable) do |re|
      if re.link.is_a?(AppIF::AppProxy)
        @localReg << re
        if store = @config.store
          store.each {|b| localDelivery(b, re.link) if re.match?(b.destEid)}
        end
      end
      subs = @subSet.subscriptions(re.destination)
      subs.each do |uri|
        if content = @config.cache[uri]
          notifySubscribers(uri, content, re.destination,
                            @config.cache.currentRevision(uri),
                            @config.cache.metadata(uri))
        end
      end
    end

    @rtEvToForward = @evDis.subscribe(:bundleToForward) do |b|
      #puts "(#{@config.localEid}, #{RdtnTime.now.sec}) bundle #{b.inspect}"
      if ccn_blk = b.findBlock(CCNBlock)
        uri = ccn_blk.uri
        case ccn_blk.method
        when :subscribe
          if @cacheSubscriptions or @config.localEid == b.srcEid
            @subSet.subscribe(uri, b.srcEid)
          end
          if @config.localEid == b.srcEid and @pollInterval and (!@pollSubscriptions.include?(uri))
            @pollSubscriptions << uri
            RdtnTime.schedule(@pollInterval) do
              if @pollSubscriptions.include? uri
                sub_bundle = Bundling::Bundle.new(nil, "dtn:internet-gw/", nil,
                                                  :multicast => true,
                                                  :lifetime => @bundleLifetime)
                sub_bundle.addBlock CCNBlock.new(sub_bundle, uri, :subscribe)
                @config.localSender.sendBundle sub_bundle
                true
              end
            end
          end
          if (@cacheSubscriptions and
              @config.localSender.localRegistrations.include? b.destEid)
            ack = Bundling::Bundle.new(nil, b.srcEid, nil,
                                       :lifetime => @bundleLifetime)
            ack.addBlock(CCNBlock.new(ack, uri, :subscription_ack))
            @config.localSender.sendBundle ack
          end
          if content = @config.cache[uri]
            notifySubscribers(uri, content, b.srcEid,
                              @config.cache.currentRevision(uri),
                              @config.cache.metadata(uri))
          end
        when :unsubscribe
          @subSet.unsubscribe(uri, b.srcEid)
        when :publish
          @config.cache.addContent(uri, b.payload, ccn_blk.revision,
                                   ccn_blk.metadata)
          @subSet.subscribers(uri).each do |subs|
            notifySubscribers(uri, b.payload, subs, ccn_blk.revision,
                              ccn_blk.metadata)
          end
        when :delete
          @config.cache.delete(uri)
        when :subscription_ack
          @pollSubscriptions.delete uri
        end
      end
      @localReg.each {|re| localDelivery(b, re.link) if re.match?(b.destEid)}
    end

    @rdEvClosed    = @evDis.subscribe(:linkClosed) do |link|
      @localReg.delete_if {|re| re.link == link}
      @queues.delete(link)
    end

    @rtEvForwarded = @evDis.subscribe(:bundleForwarded) do |b, link|
      shiftQueue(link)
      if ccn_blk = b.findBlock(CCNBlock)
        if ccn_blk.method == :publish
          link.remoteEids.each {|node| @subSet.deliveredRevision(node, ccn_blk.uri, ccn_blk.revision)}
        end
      end
    end
  end

  def stop
    @evDis.unsubscribe(:routeAvailable,  @rtEvAvailable)
    @evDis.unsubscribe(:bundleToForward, @rtEvToForward)
    @evDis.unsubscribe(:bundleForwarded, @rtEvForwarded)
    @evDis.unsubscribe(:linkClosed,      @rtEvClosed)
  end

  protected

  def notifySubscribers(uri, content, subs, rev, metadata)
    unless @subSet.hasRevision?(subs, uri, rev)
      resp_bndl = Bundling::Bundle.new(content, subs, @config.localEid,
                                       :lifetime => @bundleLifetime)
      resp_bndl.addBlock CCNBlock.new(resp_bndl, uri, :publish, {:revision=>rev}.merge(metadata))
      link = @config.contactManager.findLink {|l| subs == l.remoteEid}
      enqueue resp_bndl, link, :forward if link
    end
  end

  def localDelivery(bundle, link)
    action = bundle.destinationIsSingleton? ? :forward : :replicate
    enqueue(bundle, link, action)
  end

  def shiftQueue(link)
    unless link.busy?
      nextBundle, nextAction = @queues[link].shift
      doForward(nextBundle, link, nextAction) unless nextBundle.nil?
    end
  end

  # Add a bundle to a forwarding queue. Takes a bundle and a link.
  # Returns nil. Sends the first bundle from the queue to the CL if the link
  # is not busy.
  def enqueue(bundle, link, action = :forward)
    @queues[link] << [bundle, action]
    shiftQueue link
    nil
  end

  # Adds a list of bundles to the forwarding queue. Takes a list of bundles and
  # a link. Returns nil. Sorts the whole queue after adding the new bundles. If
  # the link is not busy, the first bundle from the queue is sent.
  def bulkEnqueue(bundles, link, action = :forward)
    @queues[link] += bundles.map {|b| [b, action]}
    shiftQueue link
    nil
  end

  private

  def doForward(bundle, link, action = :forward)
    begin
      neighbor   = link.remoteEid
      rdebug("Singleton #{bundle.destinationIsSingleton?}, #{bundle.destEid}")
      singleDest = bundle.destinationIsSingleton? ? bundle.destEid : nil
      if @config.forwardLog[bundle.bundleId].shouldAct?(action, neighbor, link, singleDest)
	@config.forwardLog[bundle.bundleId].addEntry(action, :inflight, neighbor, link)

	# FIXME: unsubscribe
	@evDis.subscribe(:transmissionError) do |b, l|
	  if b.bundleId == bundle.bundleId and l == link
	    @config.forwardLog[b.bundleId].updateEntry(action, :transmissionError, neighbor, l)
	  end
	end

	link.sendBundle(bundle)
	rinfo("Forwarded bundle (dest: #{bundle.destEid}) over #{link.name}.")
	@evDis.dispatch(:bundleForwarded, bundle, link, action)
      end
    rescue ProtocolError, SystemCallError, IOError => err
      rerror("Router::doForward #{err.class}: #{err}")
      @evDis.dispatch(:transmissionError, bundle, link)
    end
    return nil
  end
  
end

class RouterReg

  include Singleton

  attr_accessor :routers

  def initialize
    @routers = {}
  end

  def regRouter(name, klass)
    @routers[name] = klass
  end

end

def regRouter(name, klass)
  RouterReg.instance.regRouter(name, klass)
end

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

  def initialize(config, evDis)
    @config   = config
    @evDis    = evDis
    @localReg = []
    @queues   = Hash.new {|h, k| h[k] = []}
    @config.registerComponent(:router, self) {self.stop}

    @rtEvAvailable = @evDis.subscribe(:routeAvailable) do |re|
      if re.link.is_a?(AppIF::AppProxy)
        @localReg << re
        if store = @config.store
          store.each {|b| localDelivery(b, [re.link]) if re.match?(b.destEid)}
        end
      end
    end

    @rtEvToForward = @evDis.subscribe(:bundleToForward) do |b|
      links = @localReg.find_all {|re| re.match?(b.destEid)}.map {|re| re.link}
      localDelivery(b, links) unless links.empty?
    end

    @rdEvClosed    = @evDis.subscribe(:linkClosed) do |link|
      @localReg.delete_if {|re| re.link == link}
    end
  end

  def stop
    @evDis.unsubscribe(:routeAvailable,  @rtEvAvailable)
    @evDis.unsubscribe(:bundleToForward, @rtEvToForward)
    @evDis.unsubscribe(:linkClosed,      @rtEvClosed)
  end

  protected

  def localDelivery(bundle, links)
    action = bundle.destinationIsSingleton? ? :forward : :replicate
    enqueue(bundle, links, action)
  end

  # Add a bundle to the forwarding queues. Takes a bundle and a list of links.
  # Returns nil. For each link in links, sends the bundle to the CL if the link
  # is not busy, otherwise adds it to the queue to be sent when the link is
  # ready.
  def enqueue(bundle, links, action = :forward)
    links.each do |link|
      if link.busy?
	@queues[link] << [bundle, action]
      else
	doForward(bundle, link, action)
      end
    end
  end

  private

  def doForward(bundle, link, action = :forward)
    begin
      neighbor   = link.remoteEid
      rdebug("Singleton #{bundle.destinationIsSingleton?}, #{bundle.destEid}")
      singleDest = bundle.destinationIsSingleton? ? bundle.destEid : nil
      if bundle.forwardLog.shouldAct?(action, neighbor, link, singleDest)
	if defined?(link.maxBundleSize) and link.maxBundleSize
	  fragments = bundle.fragmentMaxSize(link.maxBundleSize)
	else
	  fragments = [bundle]
	end
	fragments.each do |frag|
	  frag.forwardLog.addEntry(action, :inflight, neighbor, link)

	  # FIXME: unsubscribe
	  @evDis.subscribe(:transmissionError) do |b, l|
	    if b.bundleId == frag.bundleId and l == link
	      b.forwardLog.updateEntry(action, :transmissionError, neighbor, l)
	    end
	  end

	  link.sendBundle(frag)
	  rinfo("Forwarded bundle (dest: #{bundle.destEid}) over #{link.name}.")
	  @evDis.dispatch(:bundleForwarded, frag, link, action)
	end
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

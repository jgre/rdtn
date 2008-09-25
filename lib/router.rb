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

  def initialize(daemon)
    @daemon   = daemon
    @config   = daemon.config
    @config.registerComponent(:router, self) {self.stop}
    @evDis    = daemon.evDis
    @localReg = []

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
  end

  def stop
    @evDis.unsubscribe(:routeAvailable, @rtEvAvailable)
    @evDis.unsubscribe(:bundleToForward, @rtEvToForward)
  end

  protected

  def localDelivery(bundle, links)
    action = bundle.destinationIsSingleton? ? :forward : :replicate
    doForward(bundle, links, action)
  end
 
  # Forward a bundle. Takes a bundle and a list of links. Returns nil.
  # modified to optionally drop random bundles
  def doForward(bundle, links, action = :forward)
    links.each do |link|
      begin
	neighbor   = link.remoteEid
	rdebug("Singleton #{bundle.destinationIsSingleton?}, #{bundle.destEid}")
	singleDest = bundle.destinationIsSingleton? ? bundle.destEid : nil
	unless bundle.forwardLog.shouldAct?(action, neighbor, link, singleDest)
	  next
	end
	if defined?(link.maxBundleSize) and link.maxBundleSize
	  fragments = bundle.fragmentMaxSize(link.maxBundleSize)
	else
	  fragments = [bundle]
	end
	fragments.each do |frag|
	  frag.forwardLog.addEntry(action, :inflight, neighbor, link)
	  link.sendBundle(frag)
	  rinfo("Forwarded bundle (dest: #{bundle.destEid}) over #{link.name}.")
	  @evDis.dispatch(:bundleForwarded, frag, link, action)
	end
      rescue ProtocolError, SystemCallError, IOError => err
	bundle.forwardLog.updateEntry(action,:transmissionError,neighbor,link)
	rerror("Routetab::doForward #{err}")
      end
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

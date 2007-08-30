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

class RoutingEntry
  attr_reader :destination,
    	      :exclusive

  def initialize(dest, link, exclusive = false)
    @destination = Regexp.new(dest.to_s)
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

end

class RoutingTable < Monitor

  def initialize(contactManager)
    super()
    @log = RdtnConfig::Settings.instance.getLogger(self.class.name)
    @routes=[]
    @contactManager = contactManager

    EventDispatcher.instance().subscribe(:routeAvailable) do |*args|
      self.addEntry(*args)
    end
    EventDispatcher.instance.subscribe(:routeLost) do |*args|
      deleteEntry(*args)
    end
    EventDispatcher.instance.subscribe(:bundleParsed) do |*args|
      forward(*args)
    end
  end

  def print
    @routes.each do |entry|
      puts "#{entry.destination}\t#{entry.link}\t#{entry.exclusive}"
    end
  end

  def addEntry(routingEntry)
    @log.info(
      "Added route to #{routingEntry.destination.source} over #{routingEntry.link}.")
    synchronize { @routes.push(routingEntry) }

    # See if we can send stored bundles over this link.
    store = RdtnConfig::Settings.instance.store
    if store
      bundles = store.getBundlesMatchingDest(routingEntry.destination)
      bundles.each {|bundle| doForward(bundle, [routingEntry.link])}
    end
  end

  def deleteEntry(link, dest = nil)
    synchronize do
      @routes.delete_if do |entry|
	if entry.link(@contactManager).to_s == link.to_s and (not dest or dest.to_s == entry.destination.source)
	  true
	else
	  false
	end
      end
    end
  end

  def match(dest)
    synchronize {@routes.find_all {|entry| entry.destination === dest} }
  end

  def forward(bundle)
    @log.debug("Forward: #{bundle.destEid}, #{bundle.srcEid}")
    matches = self.match(bundle.destEid.to_s)

    # Avoid returning the bundle directly to its sender.
    matches.delete_if do |entry| 
      l = entry.link(@contactManager)
      if l
	l == bundle.incomingLink
      else
	true
      end
    end
    
    exclusiveLink = matches.find {|entry| entry.exclusive}
    matches = [exclusiveLink] if exclusiveLink
    links = matches.map {|entry| entry.link(@contactManager)}
    doForward(bundle, links)
    return nil
  end

  private

  # Forward a bundle. Takes a bundle and a list of links. Returns nil.
 
  def doForward(bundle, links)
    links.each do |link|
      begin
	if defined?(link.maxBundleSize) and link.maxBundleSize
	  fragments = bundle.fragmentMaxSize(link.maxBundleSize)
	else
	  fragments = [bundle]
	end
	fragments.each do |frag| 
	  link.sendBundle(frag) 
	  @log.info(
               "Forwarded bundle (dest: #{bundle.destEid}) over #{link.name}.")
	  EventDispatcher.instance.dispatch(:bundleForwarded, frag, link)
	end
      rescue ProtocolError => err
	@log.error("Routetab::doForward #{err}")
      end
    end
    return nil
  end
  
end

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
#
# $Id: rdtnconfig.rb 84 2007-04-02 18:55:20Z jgre $

require 'singleton'
require "rdtnevent"
require "cl"
require "eidscheme"
require "storage"
require "contactmgr"

class RoutingTable

  def initialize
    @routes={}

    EventDispatcher.instance().subscribe(:routeAvailable) do |dest, link|
      #sself.contactEstablished(*args)
      self.addEntry(dest, link)
    end
    EventDispatcher.instance.subscribe(:bundleParsed) do |bundle|
      RdtnLogger.instance.debug("Bundle Parsed: #{bundle.destEid}, #{bundle.srcEid}")
      links = self.match(bundle.destEid.to_s)
      # TODO policy to decide, if we forward over multiple links or just over
      # one.
      forward(bundle, links)
    end
  end

  include Singleton

  def addEntry(dest, link)
    RdtnLogger.instance.info("Added route to #{dest} over #{link}.")
    @routes[Regexp.new(dest.to_s)]=link
    # See if we can send stored bundles over this link.
    bundles = Storage.instance.getBundlesMatchingDest(dest)
    bundles.each {|bundle| self.forward(bundle, [link])}
  end

  def contactEstablished(link)
    if not defined?(link.remoteEid) or not link.remoteEid 
      raise RuntimeError, "Could not determine the EID of the new contact on link #{link.object_id}"
    end
    RdtnLogger.instance.info("Established contact on #{link.object_id} to #{link.remoteEid}")
    eid = link.remoteEid
    self.addEntry(eid.indexingPart, link)
  end


  def match(dest)
    res=[]
    @routes.each_pair{|d,l|
      if(d.match(dest))
        res << l
      end
    }
    return res
  end

  private

  # Forward a bundle. Takes a bundle and a list of links. Returns nil.
 
  def forward(bundle, links)
    links.each do |link|
      if not link.kind_of?(Link)
	link = ContactManager.instance.findLink do |lnk| 
	  lnk.name and lnk.name == link
	end
	if not link.kind_of?(Link)
	  next
	end
      end
      begin
	if defined?(link.maxBundleSize) and link.maxBundleSize
	  fragments = bundle.fragmentMaxSize(link.maxBundleSize)
	else
	  fragments = [bundle]
	end
	fragments.each do |frag| 
	  link.sendBundle(frag) 
	  RdtnLogger.instance.info("Forwarded bundle (dest: #{bundle.destEid}) over #{link.name}.")
	  EventDispatcher.instance.dispatch(:bundleForwarded, frag, link)
	end
	return nil
      rescue ProtocolError => err
	RdtnLogger.instance.error("Routetab::forward #{err}")
      end
      #link.sendBundle(bundle)
    end
    return nil
  end
  
end

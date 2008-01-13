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

class Router

  protected
 
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
	  rinfo(self, 
               "Forwarded bundle (dest: #{bundle.destEid}) over #{link.name}.")
	  EventDispatcher.instance.dispatch(:bundleForwarded, frag, link)
	end
      rescue ProtocolError, SystemCallError, IOError => err
	rerror(self, "Routetab::doForward #{err}")
      end
    end
    return nil
  end
  
end

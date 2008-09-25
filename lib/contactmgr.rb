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
require "bundle"
require "cl"
require "eidscheme"
require "monitor"
require "rdtntime"

class ContactManager < Monitor

  attr_reader :links
 
  # The housekeeping timer determines the interval between checks for idle
  # links.
  def initialize(config, evDis, housekeepingTimer = 300)
    super()
    @config = config
    @evDis = evDis
    @oppCount  = 0 # Counter for the name of opportunistic links.
    @links     = []
    @config.registerComponent(:contactManager, self)

    @evDis.subscribe(:linkCreated) do |*args| 
      linkCreated(*args)
    end
    @evDis.subscribe(:linkClosed) do |*args|
      contactClosed(*args)
    end
    @evDis.subscribe(:opportunityAvailable) do |*args|
      opportunity(*args)
    end
    @evDis.subscribe(:opportunityDown) do |*args|
      opportunityDown(*args)
    end
    @evDis.subscribe(:linkOpen) do |*args|
      linkOpen(*args)
    end

    #housekeeping(housekeepingTimer)
  end

  def findLinkByName(name)
    findLink { |lnk| lnk.name and lnk.name == name }
  end

  def findLink(&block)
    synchronize do
      return @links.find(&block)
    end
  end

  private
 
  def linkCreated(link)
    rdebug("Link created #{link.name}")
    synchronize do
      @links << link
    end
  end

  def contactClosed(link)
    @evDis.dispatch(:routeLost, link)
    rdebug("Removing link #{link.object_id} from ContactManager")
    synchronize do
      @links.delete(link)
    end
  end

  def opportunity(type, options, eid = nil)
    return nil if eid and findLink {|lnk| eid == lnk.remoteEid}

    clClasses = CLReg.instance.cl[type]
    if clClasses
      begin
	rdebug("Opportunity for #{type} link to #{eid}.")
	link = clClasses[1].new(@config, @evDis)
	link.policy = :opportunistic
	link.remoteEid = eid
	link.open("opportunistic#{@oppCount}", options)
	@oppCount += 1

      rescue RuntimeError => err
	rerror("Failed to open opportunistic link #{err}")
      end
    else
      rwarn("Opportunity signaled with unknown type #{type}")
      return nil
    end
  end

  def opportunityDown(type, options, eid)
    # FIXME use type and options, if eid is not given
    rinfo("Opportunity down #{eid}")
    link=findLink {|lnk| lnk.remoteEid == eid and lnk.policy == :opportunistic}
    rinfo("Closing opportunistic link #{link}") if link
    link.close if link
  end

  def linkOpen(link)
    if link.remoteEid
      @evDis.dispatch(:routeAvailable, RoutingEntry.new(link.remoteEid, link))
    end
  end

  # Housekeeping starts a thread that wakes up every +timer+ seconds and deletes
  # all opportunistic links from +@links+ that are not busy.
  
  def housekeeping(timer)
    Thread.new(timer) do |ti|
      while true
	RdtnTime.rsleep(timer)
	synchronize do
	  @links.delete_if {|lnk| lnk.policy != :alwaysOn and not lnk.busy?}
	end
      end
    end
  end

end

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
require "configuration"
require "cl"
require "eidscheme"
require "monitor"

class Neighbor

  attr_accessor :eid,
                :lastContact,
		:downSince,
		:nContacts,
		:totalContactDuration,
		:totalDowntime,
		:curLink

  def initialize(eid)
    @eid                  = eid
    @lastContact          = nil
    @downSince            = nil
    @nContacts            = 0
    @totalContactDuration = 0
    @totalDowntime        = 0
    @curLink              = nil
  end

  def currentContactDuration
    if @downSince or not @lastContact: 0
    else Time.now - @lastContact
    end
  end

  def currentDowntime
    if @downSince: Time.now - @downSince
    else 0
    end
  end

  def contactStarts(link)
    @lastContact    = Time.now
    @totalDowntime += currentDowntime
    @downSince      = nil
    @nContacts     += 1
    @curLink        = link
  end

  def contactEnds
    @totalContactDuration += currentContactDuration
    @downSince = Time.now
    @curLink   = nil
  end

  def isContactOpen?
    not @downSince
  end

  def averageContactDuration
    if nContacts > 0
      (@totalContactDuration + currentContactDuration)/ @nContacts
    else 0
    end
  end

  def averageDowntime
    if nContacts > 0: (@totalDowntime + currentDowntime) / @nContacts
    else 0
    end
  end

end

class ContactManager < Monitor
 
  # The housekeeping timer determines the interval between checks for idle
  # links.
  def initialize(housekeepingTimer = 300)
    super()
    @oppCount  = 0 # Counter for the name of opportunistic links.
    @links     = []
    @neighbors = []

    EventDispatcher.instance().subscribe(:linkCreated) do |*args| 
      linkCreated(*args)
    end
    EventDispatcher.instance().subscribe(:linkClosed) do |*args|
      contactClosed(*args)
    end
    EventDispatcher.instance().subscribe(:opportunityAvailable) do |*args|
      opportunity(*args)
    end
    EventDispatcher.instance().subscribe(:opportunityDown) do |*args|
      opportunityDown(*args)
    end
    EventDispatcher.instance().subscribe(:linkOpen) do |*args|
      linkOpen(*args)
    end

    housekeeping(housekeepingTimer)
  end

  def findLinkByName(name)
    findLink { |lnk| lnk.name and lnk.name == name }
  end

  def findLink(&block)
    synchronize do
      return @links.find(&block)
    end
  end

  def findNeighbor(&block)
    synchronize do
      return @neighbors.find(&block)
    end
  end

  def findNeighborByEid(eid)
    findNeighbor {|n| n.eid.to_s == eid.to_s }
  end

  private
 
  def linkCreated(link)
    rdebug(self, "Link created #{link.name}")
    synchronize do
      @links << link
    end
  end

  def contactClosed(link)
    EventDispatcher.instance.dispatch(:routeLost, link)
    rdebug(self,
	"Removing link #{link.object_id} from ContactManager")
    synchronize do
      @links.delete(link)
    end
    if link.remoteEid
      neighbor = findNeighborByEid(link.remoteEid)
      neighbor.contactEnds if neighbor
    end
  end

  def opportunity(type, options, eid = nil)
    neighbor = findNeighborByEid(eid)
    return nil if eid and neighbor and neighbor.isContactOpen?

    clClasses = CLReg.instance.cl[type]
    if clClasses
      begin
	rdebug(self, "Opportunity for #{type} link to #{eid}.")
	link = clClasses[1].new
	link.policy = :opportunistic
	link.remoteEid = eid
	link.open("opportunistic#{@oppCount}", options)
	@oppCount += 1

	#EventDispatcher.instance.dispatch(:routeAvailable, 
	#				  RoutingEntry.new(eid, link)) if eid
      rescue RuntimeError => err
	rerror(self, "Failed to open opportunistic link #{err}")
      end
    else
      rwarn(self, "Opportunity signaled with unknown type #{type}")
      return nil
    end
  end

  def opportunityDown(type, options, eid)
    # FIXME use type and options, if eid is not given
    rinfo(self, "Opportunity down #{eid}")
    link=findLink {|lnk| lnk.remoteEid == eid and lnk.policy == :opportunistic}
    rinfo(self, "Closing opportunistic link #{link}") if link
    link.close if link
  end

  def linkOpen(link)
    if link.remoteEid
      neighbor = findNeighborByEid(link.remoteEid)
      if not neighbor
	neighbor = Neighbor.new(link.remoteEid)
	synchronize { @neighbors.push(neighbor) }
      end
      neighbor.contactStarts(link)
      EventDispatcher.instance.dispatch(:neighborContact, neighbor, link)
#      EventDispatcher.instance.dispatch(:routeAvailable, RoutingEntry.new(
#				        link.remoteEid, link))
    end
  end

  # Housekeeping starts a thread that wakes up every +timer+ seconds and deletes
  # all opportunistic links from +@links+ that are not busy.
  
  def housekeeping(timer)
    Thread.new(timer) do |ti|
      while true
	sleep(timer)
	synchronize do
	  @links.delete_if {|lnk| lnk.policy != :alwaysOn and not lnk.busy?}
	end
      end
    end
  end

end

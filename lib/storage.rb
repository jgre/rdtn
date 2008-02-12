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

require "bundle"
require "monitor"
require "pstore"
require "time"

class BundleAlreadyStored < RuntimeError
  def initialize(bundleId)
    super("Bundle #{bundleId} already stored.")
  end
end

class AgeDisplacement

  def orderBundles(bundle1, bundle2)
    bundle2.creationTimestamp <=> bundle1.creationTimestamp
  end

end

class Storage < Monitor

  include Enumerable
  attr_accessor :displacement

  def initialize(evDis, maxSize = nil, dir = nil)
    super()
    @evDis = evDis
    @maxSize = maxSize
    @storageDir = dir
    @curSize = 0
    @bundles = []
    @deleted = []
    @displacement = []
    #Bundling::PayloadBlock.storePolicy = :random

    #housekeeping
  end

  def each(&handler)
    synchronize { @bundles.each(&handler) }
  end

  def allIds
    bids = @bundles.map {|bundle| bundle.bundleId}
    delbids = @deleted.map {|bundle| bundle.bundleId}
    bids + delbids
  end

  def getBundle(bundleId)
    getBundleMatching {|bundle| bundle.bundleId == bundleId}
  end

  def deleteBundle(bundleId)
    synchronize do 
      @bundles.delete_if do |bundle| 
      	if bundle.bundleId == bundleId
      	  @curSize -= bundle.payloadLength
      	  true
      	else
      	  false
      	end
      end
    end
  end

  def storeBundle(bundle)
    if /dtn:subscribe\/.*/ =~ bundle.destEid.to_s
      return nil
    end
    synchronize do
      @curSize += bundle.payloadLength
      if (@bundles + @deleted).find {|b| b.bundleId == bundle.bundleId}
	raise BundleAlreadyStored, bundle.bundleId
      end
    
      @bundles.push(bundle)
      @evDis.dispatch(:bundleStored, bundle)
      enforceLimit
    end
  end

  def clear
    synchronize do
      @bundles.clear
      @curSize = 0
    end
  end

  def getBundleMatching(&handler)
    synchronize { @bundles.find(&handler) }
  end

  def getBundleMatchingDest(destEid, includeDeleted = false)
    getBundleMatching(includeDeleted) {|bundle| bundle.destEid == destEid }
  end

  def getBundlesMatching(includeDeleted = false, &handler)
    synchronize do 
      ret = @bundles.find_all(&handler) 
      ret += @deleted.find_all(&handler) if includeDeleted
      ret
    end
  end

  def getBundlesMatchingDest(destEid, includeDeleted = false)
    getBundlesMatching(includeDeleted) {|bundle| destEid === bundle.destEid.to_s }
  end

  def save
    if @storageDir
      store=PStore.new(@storageDir)
      store.transaction { store[:bundles] = @bundles }
    end
  end

  def load
    if @storageDir
      store=PStore.new(@storageDir)
      store.transaction { @bundles = store[:bundles] }
    end
  end

  def addPriority(prio)
    @displacement.push(prio)
  end

  private
  def enforceLimit
    # FIXME remove expired bundles
    exp, bundles = @bundles.partition do |bundle|
      if bundle.expired?
	@evDis.dispatch(:bundleRemoved, bundle)
	true
      else
	false
      end
    end
    @deleted.concat(exp)
    @bundles = bundles
    #if @maxSize and @curSize > @maxSize
    #  @bundles.sort! do |b1, b2|
    #    # Accumulate the comparision from all priority algorithms to 
    #    # based on a bundle to bundle comparison.
    #    accPrio = @displacement.inject(0) do |sum, prio| 
    #      sum+prio.orderBundles(b1,b2, @neighbor)
    #    end
    #    if accPrio == 0   then 0
    #    elsif accPrio > 0 then 1
    #    else               -1
    #    end
    #  end
    #end
    
    while @maxSize and @curSize > @maxSize
      #puts "Enforcing #{@maxSize} #{@curSize}"
      
      # TODO seek a replacement for the undeleted bundle
      if (!@bundles.last.custodyAccepted?)
        outBndl = @bundles.pop
        if outBndl
	  @deleted.push(outBndl)
          @curSize -= outBndl.payloadLength
	  @evDis.dispatch(:bundleRemoved, outBndl)
        end
      end
    end
  end

  def housekeeping
    Thread.new do
      while true
	RdtnTime.rsleep(10) #FIXME variable timer
	@evDis.dispatch(:timerTick)
	
	# do i have custody for bundles?
	@bundles.each do |b| 
          # puts "#{b.bundleId} has custody? #{b.custodyAccepted?}"
          # puts "Store: creationTimestamp = #{b.creationTimestamp}"
          #                 puts "Store: creationTimestampSeq = #{b.creationTimestampSeq}"
          #                 puts "Store: srcEid = #{b.srcEid}"
          #                 puts "Store: fragmentOffset = #{b.fragmentOffset}"
          #                 puts "Store: bundleId = #{b.bundleId}"     
        end
	        
	synchronize do
	  @bundles.delete_if do |b| 
	    RdtnTime.now.to_i > (b.creationTimestamp.to_i + b.lifetime.to_i + Time.gm(2000).to_i) 
	  end
	end
      end
    end
  end

end

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
  attr_accessor :displacement, :storageDir, :maxSize

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

  def each(includeDeleted = false)
    synchronize do
      @bundles.each {|b| yield(b) if not b.deleted? or includeDeleted }
    end
  end

  def allIds
    bids = @bundles.map {|bundle| bundle.bundleId}
    delbids = @deleted.map {|bundle| bundle.bundleId}
    bids + delbids
  end

  def getBundle(bundleId)
    getBundleMatching {|bundle| bundle.bundleId == bundleId}
  end

  def deleteBundle(bundleId, purge = false)
    deleteBundles(purge) {|b| b.bundleId == bundleId}
  end

  def deleteBundles(purge = false, &handler)
    synchronize do 
      bundles = @bundles.find_all(&handler)
      bundles.each do |bundle|
	@curSize -= bundle.payloadLength
	bundle.delete
	@evDis.dispatch(:bundleRemoved, bundle)
	@bundles.delete(bundle) if purge
      end
    end
  end

  def storeBundle(bundle)
    if /dtn:subscribe\/.*/ =~ bundle.destEid.to_s
      return nil
    end
    synchronize do
      @curSize += bundle.payloadLength
      if dup = @bundles.find {|b| b.bundleId == bundle.bundleId}
	dup.forwardLog.merge(bundle.forwardLog)
	raise BundleAlreadyStored, bundle.bundleId
      end
      @bundles.push(bundle)
      @evDis.dispatch(:bundleStored, bundle)
      rdebug(self, "Stored bundle #{bundle.bundleId}: #{bundle.srcEid} -> #{bundle.destEid}")
      enforceLimit
    end
  end

  def clear
    synchronize do
      deleteBundles(true) {|b| true}
    end
  end

  def getBundleMatching
    synchronize { @bundles.find {|b| yield(b) unless b.deleted?} }
  end

  def getBundleMatchingDest(destEid, includeDeleted = false)
    getBundleMatching(includeDeleted) {|bundle| bundle.destEid == destEid }
  end

  def getBundlesMatching(includeDeleted = false)
    synchronize do 
      @bundles.find_all do |bundle|
	yield(bundle) if (not bundle.deleted?) or includeDeleted
      end
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
    deleteBundles(true) do |bundle| 
      ret = bundle.expired?
      rdebug(self, "Deleting expired bundle #{bundle.bundleId}: #{bundle.srcEid} -> #{bundle.destEid}") if ret
      ret
    end
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
    
    delCandidates = []
    delSize       = 0
    @bundles.reverse_each do |bundle|
      break unless @maxSize and (@curSize - delSize) > @maxSize
      unless bundle.deleted? or bundle.retentionConstraints?
	rdebug(self, "Deleting bundle #{bundle.bundleId}: #{bundle.srcEid} -> #{bundle.destEid}")
	delCandidates.push(bundle.bundleId)
	delSize += bundle.payloadLength
      end
    end
    unless delCandidates.empty?
      deleteBundles {|bundle| delCandidates.include?(bundle.bundleId)}
    end
  end

  def housekeeping
    Thread.new do
      while true
	RdtnTime.rsleep(10) #FIXME variable timer
	@evDis.dispatch(:timerTick)
	
	synchronize do
	  deleteBundles(true) {|bundle| bundle.expired?}
	end
      end
    end
  end

end

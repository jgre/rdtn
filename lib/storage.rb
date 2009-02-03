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
require "rdtntime"

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
  attr_accessor :displacement, :directory, :limit, :channelquota

  def initialize(config, evDis, limit = nil, dir = nil)
    super()
    @config = config
    @evDis = evDis
    @limit = limit
    @directory = dir
    @curSize = 0
    @bundles = {}
    @deleted = []
    @displacement = []
    @channelquota = nil

    @config.registerComponent(:store, self)
    #housekeeping
  end

  def length
    @bundles.values.compact.length
  end

  def each(includeDeleted = false)
    deleteBundles(true) {|bundle| bundle.expired? unless bundle.nil?}
    synchronize do
      @bundles.values.compact.each {|b| yield(b) if !b.nil? or includeDeleted }
    end
  end

  def allIds
    @bundles.keys
  end

  def getBundle(bundleId)
    getBundleMatching {|bundle| bundle.bundleId == bundleId}
  end

  def deleteBundle(bundleId, purge = false)
    deleteBundles(purge) {|b| b.bundleId == bundleId}
  end

  def deleteBundles(purge = false, &handler)
    synchronize do 
      bundles = @bundles.values.compact.find_all(&handler)
      bundles.each do |bundle|
	@curSize -= bundle.payloadLength
	bundle.delete
	@bundles[bundle.bundleId] = nil
	@evDis.dispatch(:bundleRemoved, bundle)
	@bundles.delete(bundle.bundleId) if purge
      end
    end
  end

  def storeBundle(bundle)
    #if /dtn:subscribe\/.*/ =~ bundle.destEid.to_s
    #  return nil
    #end
    synchronize do
      @curSize += bundle.payloadLength
      if dup = @bundles[bundle.bundleId]
	dup.forwardLog.merge(bundle.forwardLog) unless dup.nil?
	raise BundleAlreadyStored, bundle.bundleId
      end
      @bundles[bundle.bundleId] = bundle
      @evDis.dispatch(:bundleStored, bundle)
      rdebug("Stored bundle #{bundle.bundleId}: #{bundle.srcEid} -> #{bundle.destEid}")
      enforceLimit
      enforceChannelQuotas if @channelquota
    end
  end

  def clear
    synchronize do
      deleteBundles(true) {|b| true}
    end
  end

  def getBundleMatching
    synchronize{@bundles.values.compact.find {|b| yield(b) unless b.nil? or b.deleted?}}
  end

  def getBundleMatchingDest(destEid, includeDeleted = false)
    getBundleMatching(includeDeleted) {|bundle| bundle.destEid === Regexp.new(destEid) }
  end

  def getBundlesMatching(includeDeleted = false)
    synchronize do 
      @bundles.values.compact.find_all do |bundle|
	yield(bundle) if (not bundle.deleted?) or includeDeleted
      end
    end
  end

  def getBundlesMatchingDest(destEid, includeDeleted = false)
    getBundlesMatching(includeDeleted) {|bundle| Regexp.new(destEid) === bundle.destEid.to_s }
  end

  def save
    if @directory
      store=PStore.new(@directory)
      store.transaction { store[:bundles] = @bundles }
    end
  end

  def load
    if @directory
      store=PStore.new(@directory)
      store.transaction { @bundles = store[:bundles] }
    end
  end

  def addPriority(prio)
    @displacement.push(prio)
  end

  private

  def enforceChannelQuotas
    channels = Hash.new {|hash, key| hash[key] = []}
    delCandidates = []
    @bundles.values.compact.each {|bundle| channels[bundle.destEid] << bundle}
    channels.each_value do |bundles|
      if (diff = bundles.length - @channelquota) > 0
	delCandidates += bundles.sort_by {|b| b.creationTimestamp}[0, diff]
      end
    end

    unless delCandidates.empty?
      deleteBundles(false) {|bundle| delCandidates.include?(bundle)}
    end
  end

  def enforceLimit
    deleteBundles(true) do |bundle| 
      ret = bundle.nil? or bundle.expired?
      rdebug("Deleting expired bundle #{bundle.inspect}") if ret
      ret
    end
    #if @limit and @curSize > @limit
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
    @bundles.values.compact.reverse_each do |bundle|
      break unless @limit and (@curSize - delSize) > @limit
      unless bundle.deleted? or bundle.retentionConstraints?
	rdebug("Deleting bundle #{bundle.bundleId}: #{bundle.srcEid} -> #{bundle.destEid}")
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
	
	synchronize do
	  deleteBundles(true) {|bundle| bundle.expired?}
	end
      end
    end
  end

end

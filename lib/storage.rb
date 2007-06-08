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
# $Id: fileup.py 8 2006-12-22 20:00:21Z jgre $


# Bundle information relevant to storage and internal processing

require "pstore"
require "singleton"


class BundleInfo
  attr_accessor :destEid, :srcEid, :creationTimestamp, :lifetime, :bundleId

  
  def initialize(bundle)
    @destEid=bundle.destEid
    @srcEid=bundle.srcEid
    @creationTimestamp=bundle.creationTimestamp
    @lifetime=bundle.lifetime
    @bundleId=bundle.bundleId
  end

  def to_s
    @destEid.to_s + @srcEid.to_s + @creationTimestamp.to_s + @lifetime.to_s + @bundleId.to_s
    # FIXME: compute Hash
  end

end




class Storage

  @bundleIds                    # list of ids (strings)
  @bundles                      # Hash id => bundle
  @bundleInfos                  # Hash of id => BundleInfo


  def initialize
    @bundleIds = []
    @bundles = {}
    @bundleInfos = {}
    EventDispatcher.instance.subscribe(:bundleParsed) do |bundle|
      self.storeBundle(bundle)
      self.save
    end
  end

  include Singleton
  
  def listBundles
    # return list of ids
    @bundleIds
  end

  def getBundleInfo(bundleId)
    # return BundleInfo
    @bundleInfos[bundleId]
  end

  def getBundle(bundleId)
    # return bundle
    @bundles[bundleId]
  end

  def storeBundle(bundle)
    bi=BundleInfo.new(bundle)
    id=bi.to_s
    if(@bundleInfos.has_key?(id))
      puts ("id collision")
    end
    @bundleIds.push(id)
    @bundleInfos[id]=bi
    @bundles[id]=bundle
  end

   def save
    store=PStore.new(RDTNConfig.instance.storageDir)
    store.transaction do
       store["bundleIds"] = @bundleIds
       store["bundleInfos"] = @bundleInfos
       store["bundles"] = @bundles
    end
  end
  
  def load
    store=PStore.new(RDTNConfig.instance.storageDir)
    store.transaction do
      @bundleIds = store["bundleIds"]
      @bundleInfos = store["bundleInfos"]
      @bundles = store["bundles"]
    end
  end


  def getBundlesMatching()
    # get all Bundles with a destination EID matching eidPrefix
    # returns matching bundles as a list of ids

    res=[]
    0.upto(@bundleInfos.length()-1) do |i|
      bi=@bundleInfos[@bundleIds[i]]
      if yield(bi)
        res << @bundles[@bundleIds[i]]
      end
    end
    return res
  end

  def getBundlesMatchingDest(destEid)
    blist=getBundlesMatching() do |bundleInfo|
      r=Regexp.new(destEid.to_s)
      #puts bundleInfo.destEid.to_s =~ r
      #puts bundleInfo.destEid, destEid
      r =~ bundleInfo.destEid.to_s
    end
    
  end


end



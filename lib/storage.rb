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


class BundleInfo
  attr_accessor :dest_eid, :src_eid, :creation_timestamp, :lifetime, :bundleId

  
  def initialize(bundle)
    @dest_eid=bundle.dest_eid
    @src_eid=bundle.src_eid
    @creation_timestamp=bundle.creation_timestamp
    @lifetime=bundle.lifetime
    @bundleId=bundle.bundleId
  end

  def to_s
    @dest_eid.to_s + @src_eid.to_s + @creation_timestamp.to_s + @lifetime.to_s + @bundleId.to_s
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
  end
  
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

   def save(filename)
    store=PStore.new(filename)
    store.transaction do
       store["bundleIds"] = @bundleIds
       store["bundleInfos"] = @bundleInfos
       store["bundles"] = @bundles
    end
  end
  
  def load(filename)
    store=PStore.new(filename)
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
        res << i
      end
    end
    return res
  end

  def getBundlesMatchingDest(destEid)
    blist=getBundlesMatching() do |bundleInfo|
      r=Regexp.new("#{destEid}")
      bundleInfo.dest_eid =~ r
    end
    
  end


end



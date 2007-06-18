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

require "fileutils"
require "pstore"
require "singleton"
require "rdtnevent"



class BundleInfo

  attr_accessor :destEid, :srcEid, :creationTimestamp, :lifetime, :bundleId, :fragmentOffset
  
  def initialize(bundle)
    @destEid = bundle.destEid.to_s
    @srcEid = bundle.srcEid.to_s
    @creationTimestamp = bundle.creationTimestamp
    @lifetime = bundle.lifetime
    @bundleId = bundle.bundleId
    @fragmentOffset = bundle.fragmentOffset
  end

  def to_s
    @destEid + "-" + @srcEid + "-" + @creationTimestamp.to_s + "-" + @lifetime.to_s + "-" + @bundleId.to_s
  end

  #override the method eql? for Hash key equality. 
  def eql?(other)
    return (self.class == other.class) \
	   && (@destEid == other.destEid) \
           && (@srcEid == other.srcEid) \
           && (@creationTimestamp == other.creationTimestamp) \
           && (@lifetime == other.lifetime) \
           && (@bundleId == other.bundleId) \
           && (@fragmentOffset == other.fragmentOffset)
  end

  def hash
    return @destEid.hash ^ @srcEid.hash ^ @creationTimestamp.hash \
           ^ @lifetime.hash ^ @bundleId.hash ^ @fragmentOffset.hash
  end

end#BundleInfo


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
    store=PStore.new(RdtnConfig::Settings.instance.storageDir)
    store.transaction do
       store["bundleIds"] = @bundleIds
       store["bundleInfos"] = @bundleInfos
       store["bundles"] = @bundles
    end
  end
  
  def load
    store=PStore.new(RdtnConfig::Settings.instance.storageDir)
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
      r =~ bundleInfo.destEid.to_s
    end
    
  end

end#Storage


class Storage_perBundle
#every bundle will be saved in a separate file.
  attr_reader :bundleInfos
  
  Metainfo_Filename = "Metainfo.pstore"

  def initialize(mfname=Metainfo_Filename)
    mfbasename = File.basename(mfname)
    @pathname = RDTNConfig.instance.storageDir
    FileUtils.mkdir_p(@pathname)
    @bundleInfos = PStore.new(File.join(@pathname, mfbasename)) #{metaInfo, filename}
    EventDispatcher.instance.subscribe(:bundleParsed) do |bundle|
      self.save(bundle)
    end
  end

  def self.create_filename(bundle)
    dest = bundle.destEid.hash
    src = bundle.srcEid.hash
    timestamp = bundle.creationTimestamp.hash
    fragmentOffset = bundle.fragmentOffset.hash
    return "s#{src}d#{dest}t#{timestamp}f#{fragmentOffset}.pstore"
  end

  #persist bundle and it's infos. public interface
  def save(bundle) 
    fn = File.join(@pathname, Storage_perBundle.create_filename(bundle))
    metaInfo = BundleInfo.new(bundle)
    @bundleInfos.transaction do
      if @bundleInfos.root?(metaInfo)
	puts "Bundle: #{bundle} has already been stored as file: #{fn}."
      else
	@bundleInfos[metaInfo] = fn
      end
    end
    _save(fn, bundle)
  end

  def timeToDie?(bundleInfo)
    toDie = false
    @bundleInfos.transaction(true) do
      if @bundleInfos.root?(bundleInfo)
	#FIXME: - Time.gm(2000) in bundle.initialize => normalize(Time.now)
	toDie = (bundleInfo.creationTimestamp + bundleInfo.lifetime) < (Time.now - Time.gm(2000)).to_i
      end
    end
    return toDie
  end
  
  #delete the bundle and it's Info, if it has expired
  def delete_expired(bundleInfo)
    if timeToDie?(bundleInfo)
      @bundleInfos.transaction do
	_delete(@bundleInfos[bundleInfo]) 
	@bundleInfos.delete(bundleInfo)
      end
    end
  end

  #load bundles, which are not expired
  def load(bundleInfo)
    delete_expired(bundleInfo)
    filename = nil
    @bundleInfos.transaction(true) do
      if @bundleInfos.root?(bundleInfo)
	filename = @bundleInfos[bundleInfo]
      else
	puts "No bundleinfo: #{bundleInfo} has been stored."
	@bundleInfos.abort
      end
    end
    if filename
      return _load(filename)  
    end
    return nil #TODO: raise NoSuchBundle, "No #{bundleInfo} has been stored."
  end
  
  #get a bundleinfo list, to load the bundle you wanted with 'load'
  def get_bundleInfoList(srcEid=nil, destEid=nil,
			 creationTimestamp=nil, fragmentOffset=nil)
    @bundleInfos.transaction(true) do
      matching = @bundleInfos.roots.find_all do |metaInfo|
	match = true
	match = metaInfo.srcEid == srcEid if srcEid
	
	match &&= metaInfo.destEid == destEid if destEid
	match &&= metaInfo.creationTimestamp == creationTimestamp if creationTimestamp
	match &&= metaInfo.fragmentOffset == fragmentOffset if fragmentOffset
	return  match
      end #do
    end #transaction
    
    return matching
  end #get_bundleInfoList


  private
  
  #persist a bundle
  def _save(filename, bundle) 
    bundle_save = PStore.new(filename)
    bundle_save.transaction do
      bundle_save[:bundle] = bundle
    end
  end

  def _load(filename)
    bundle = nil
    bundle_load = PStore.new(filename)
    bundle_load.transaction(true) do
      bundle = bundle_load[:bundle]
    end
    return bundle
  end

  def _delete(filename)
    File.delete(filename)
  end
  
end #Storage_perBundle

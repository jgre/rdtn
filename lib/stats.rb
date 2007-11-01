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

require "rdtnerror"
require "configuration"
require "sdnv"
require "queue"
require "eidscheme"
require "rdtnevent"
require "bundle"
require "monitor"

module Stats

  class BundleStatEntry

    attr_reader :time, :dest, :src, :bundleId, :payloadSize, :fragment, :link

    def initialize(bundle, link=nil)
      @time        = Time.now
      @dest        = bundle.destEid
      @src         = bundle.srcEid
      @bundleId    = bundle.bundleId
      @payloadSize = bundle.payloadLength
      @fragment    = bundle.fragment?
      @link        = link
    end

    def to_s
      if @link and @link.remoteEid
	"#{@time.to_i}, #{@dest}, #{@src}, #{@bundleId}, #{@payloadSize}, #{@fragment}, #{@link.remoteEid}"
      else
	"#{@time.to_i}, #{@dest}, #{@src}, #{@bundleId}, #{@payloadSize}, #{@fragment}"
      end
    end

  end

  class ContactStatEntry

    attr_reader :time, :state, :clType, :linkName, :host, :port, :eid

    def initialize(state, clType, linkName, host, port, eid)
      @time     = Time.now
      @state    = state
      @clType   = clType
      @linkName = linkName
      @host     = host
      @port     = port
      @eid      = eid
    end

    def to_s
      "#{@time.to_i}, #{@state}, #{@clType}, #{@linkName}, #{@host}, #{@port}, #{@eid}"
    end

  end

  class StatGrabber < Monitor

    def initialize(timeFile, outStatFile, inStatFile, contactStatFile, 
		   subscribeStatFile, storeStatFile)
      super()
      # Log start time
      open(timeFile, "w") {|f| f.puts(Time.now.to_i) }
      @outFile      = outStatFile
      @inFile       = inStatFile
      @contactFile  = contactStatFile
      @subscribeStatFile = subscribeStatFile
      @storeStatFile = storeStatFile
      EventDispatcher.instance.subscribe(:bundleToForward) do |bundle|
	writeBundleStat(:in, bundle, bundle.incomingLink)
      end
      EventDispatcher.instance.subscribe(:bundleForwarded) do |bundle, link|
	writeBundleStat(:out, bundle, link)
      end
      EventDispatcher.instance.subscribe(:opportunityAvailable) do |tp, opts, eid|
	writeContactStat(:opportunity, tp, "", opts[:host], opts[:port], eid)
      end
      EventDispatcher.instance.subscribe(:linkOpen) do |link|
	type = CLReg.instance.getName(link.class)
	if type == :tcp or type == :udp
	  writeContactStat(:link, type, link.name, link.host, link.port, 
			   link.remoteEid)
	end
      end
      EventDispatcher.instance.subscribe(:neighborContact) do |neighbor, link|
	type = CLReg.instance.getName(link.class)
	if type == :tcp or type == :udp
	  writeContactStat(:contact, type, link.name, link.host, link.port, 
			   neighbor.eid)
	end
      end
      EventDispatcher.instance.subscribe(:linkClosed) do |link|
	type = CLReg.instance.getName(link.class)
	if type == :tcp or type == :udp
	  writeContactStat(:closed, type, link.name, link.host, link.port, 
			   link.remoteEid)
	end
      end
      EventDispatcher.instance.subscribe(:uriSubscribed) do |uri|
	writeSubscribeStat(uri)
      end
      EventDispatcher.instance.subscribe(:bundleStored) do |bundle|
	writeStoreStat(:stored, bundle)
      end
      EventDispatcher.instance.subscribe(:bundleRemoved) do |bundle|
	writeStoreStat(:removed, bundle)
      end

    end

    def writeBundleStat(inOut, bundle, link)
      entry = BundleStatEntry.new(bundle, link)
      file  = inOut == :in ? @inFile : @outFile
      synchronize do
      open(file, "a") { |f| f.puts(entry) }
      end
    end

    def writeContactStat(state, clType, linkName, host, port, eid)
      entry = ContactStatEntry.new(state, clType, linkName, host, port, eid)
      synchronize do
      open(@contactFile, "a") {|f| f.puts(entry) }
      end
    end

    def writeSubscribeStat(uri)
      synchronize do
	open(@subscribeStatFile, "a") {|f| f.puts(uri) }
      end
    end

    def writeStoreStat(status, bundle)
      synchronize do
      open(@storeStatFile, "a") do |f| 
	f.puts("#{Time.now.to_i}, #{status}, #{bundle.bundleId}")
      end
      end
    end

  end

end #module Stats


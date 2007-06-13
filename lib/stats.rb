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
# $Id$

require "rdtnlog"
require "rdtnerror"
require "rdtnconfig"
require "sdnv"
require "queue"
require "eidscheme"
require "rdtnevent"
require "bundle"

module Stats

  class StatEntry

    attr_reader :time, :dest, :src, :bundleId, :payloadSize, :fragment, :link

    def initialize(bundle, link=nil)
      @time = Time.now
      @dest = bundle.destEid
      @src = bundle.srcEid
      @bundleId = bundle.srcEid.to_s + bundle.creationTimestamp.to_s + bundle.creationTimestampSeq.to_s
      @payloadSize = bundle.payload.size
      @fragment = bundle.fragment?
      @link = link
    end

    def to_s
      "#{@time.to_i}, #{@dest}, #{@src}, #{@bundleId}, #{@payloadSize}, #{@fragment}"
    end

  end

  class StatGrabber

    def initialize(outStatFile, inStatFile)
      @inStats = []
      @outStats = []
      EventDispatcher.instance.subscribe(:bundleParsed) do |bundle|
	entry = StatEntry.new(bundle)
	@inStats << entry
	open(inStatFile, "a") { |inF| inF.puts(entry) }
      end
      EventDispatcher.instance.subscribe(:bundleForwarded) do |bundle, link|
	entry = StatEntry.new(bundle, link)
	@outStats << entry
	open(outStatFile, "a") { |outF| outF.puts(entry) }
      end
    end

  end

end #module Stats


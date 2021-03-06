#  Copyright (C) 2007, 2008 Janico Greifenberg <jgre@jgre.org> and 
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

module Bundling

  class ForwardLog

    Struct.new("ForwardLogEntry", :action, :status, :neighbor, :link, :time)

    def self.registerComponent(config, evDis)
      log = Hash.new {|h, k| h[k] = ForwardLog.new}
      config.registerComponent(:forwardLog, log)
    end

    def initialize
      @logEntries = []
      # :action can be one of :incoming, :replicate, :forward
      # :status is :infligh, :transmitted, :transmissionError,
      # :transmissionPending
    end

    def inspect
      @logEntries.map {|le| "  #{le.action} #{le.status} #{le.neighbor}"}.join("\n")
    end

    def addEntry(action, status, neighbor, link = nil, time = RdtnTime.now)
      # We convert the time to an integer and back again, as the microseconds do
      # not survive serialization.
      @logEntries.push(Struct::ForwardLogEntry.new(action, status, neighbor, 
						   link, Time.at(time.to_i)))
    end

    def updateEntry(action, status, neighbor, link = nil, time = RdtnTime.now)
      entry = @logEntries.find do |entry|
	(entry.status == :inflight and entry.action == action and 
	 (entry.neighbor == neighbor or entry.link == link))
      end
      if entry
	entry.status = status
	entry.time   = time
      else
	addEntry(action, status, neighbor, link, time)
      end
    end

    def getLatestEntry
      @logEntries[-1]
    end

    def incomingLink
      if incoming = @logEntries.find {|le| le.action == :incoming}
        incoming.link
      end
    end

    attr_accessor :logEntries

    def merge(fwlog)
      @logEntries += fwlog.logEntries
    end

    def deepCopy
      ret = ForwardLog.new
      ret.logEntries = @logEntries.map {|e| e.clone}
      ret
    end

    def shouldAct?(action, neighbor, link, singletonReceiver)
      ret = @logEntries.all? do |entry|
	if entry.status == :transmissionError
	  true
	else
	  case entry.action
	  when :forward 
	    rdebug("shouldAct? No, was already forwarded.")
	    false
	  when :replicate
	    ret=(entry.neighbor != neighbor and entry.link != link and
	     (singletonReceiver.nil? or entry.neighbor!=singletonReceiver))

	    rdebug("shouldAct? No, was already replicated to the right place.") unless ret
	    ret
	  when :incoming
	    ret = (entry.neighbor.to_s != neighbor.to_s and entry.link != link)
	    rdebug("shouldAct? No, we have it from him (#{neighbor}).") unless ret
	    ret
	  end
	end
      end
      ret
    end

    def nCopies
      cps = @logEntries.find_all do |entry|
	entry.status != :transmissionError and entry.action == copy
      end
      cps.length
    end

    def marshal_dump
      @logEntries.map do |e|
	cp = e.clone
	cp.link = nil # We cannot serialize link objects
	cp
      end
    end

    def marshal_load(entries)
      @logEntries = entries
    end

  end

end # module

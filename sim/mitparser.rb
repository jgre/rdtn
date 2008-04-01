#  Copyright (C) 2008 Janico Greifenberg <jgre@jgre.org> and 
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

$:.unshift File.join(File.dirname(__FILE__), "..", "lib")

require 'rdtnevent'
require 'eventqueue'
require 'traceparser'

module Sim

  class MITParser

    attr_reader :events

    def initialize(duration, granularity, options)
      @duration    = duration
      @granularity = granularity
      @events      = EventQueue.new
      @startTime   = options["startTime"] || 0
      @endTime     = options["endTime"]
      @startTime   = @startTime.to_i
      @endTime     = @endTime.to_i
      puts "Start: #@startTime, End: #@endTime"
      open(options["tracefile"]) {|f| process(f)} if options.has_key?("tracefile")
    end

    private

    MIT_RE = /@(\d+) (\d+) <-> (\d+) (up|down)/

    def process(file)
      puts "Processing MIT reality mining data..."
      file.each do |line|
	if MIT_RE =~ line
	  time  = $1.to_i
	  node1 = $2.to_i
	  node2 = $3.to_i
	  type  = case $4
		  when "up"   then :simConnection
		  when "down" then :simDisconnection
		  end
	  if time >= @startTime and (@endTime.nil? or time <= @endTime)
	    @events.addEvent(time - @startTime, node1, node2, type)
	  end
	end
      end
      puts "#{@events.events.length} events"
      puts "Processing done."
    end
  end

end # module

Sim::TraceParserReg.instance.reg(:mitParser, Sim::MITParser)

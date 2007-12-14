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

$:.unshift File.join(File.dirname(__FILE__), "..", "lib")

require 'remconf'
require 'rdtnevent'
require 'eventqueue'

module Rem

  class SetdestNode

    attr_accessor :id, :pos, :dest, :speed

    def initialize(id)
      @id       = id
      @pos      = [0, 0]
      @dest     = [0, 0]
      @speed    = 0
      @contacts = {}
    end

    def x=(x)
      @pos[0] = x
    end

    def y=(y)
      @pos[1] = y
    end

    def move(nSec)
      diffVec = [@dest[0] - @pos[0], @dest[1] - @pos[1]]
      dist = Math.hypot(diffVec[0], diffVec[1])
      unless dist == 0
	unitVec = [diffVec[0] / dist, diffVec[1] / dist]
	@pos = [@pos[0] + (unitVec[0] * speed * nSec),
	  @pos[1] + (unitVec[1] * speed * nSec)]
      end
    end

    def print_pos
      puts "#{@id} #{@pos[0]} #{@pos[1]}"
    end

  end

  class Contact

    attr_accessor :node1, :node2, :times, :open

    def Contact.getId(node1, node2)
      return "#{node1.id}-#{node2.id}"
    end

    def initialize(node1, node2)
      @node1 = node1
      @node2 = node2
      @open  = false
      @times = []
    end

    def calculateContact(time)
      diffVec = [@node1.pos[0] - @node2.pos[0], @node1.pos[1] - @node2.pos[1]]
      dist = Math.hypot(diffVec[0], diffVec[1])
      if dist <= Config.instance.contactDistance
	#@contacts[node2.id] = [[$time, $time]] unless @contacts.has_key?(node2.id)
	if @open
	  @times[-1][1] = time
	  return :unchanged
	else
	  @times.push([time, time])
	  #puts "Time: #{time}"
	  #puts "Dist: #{dist} #{time.to_f} (#{Config.instance.contactDistance})"
	  @open = true
	  return :remConnection
	end
      else
	if @open
	  @open = false
	  return :remDisconnection
	else
	  return :unchanged
	end
      end
    end

    def list_contacts(fDist, fDur)
      #nContacts = 0
      #uniqueContacts = @contacts.length
      #durations = []
      #@contacts.each do |id, contList|
      #  nContacts += contList.length
      #  d = contList.map {|startT, endT| [@id, id, endT - startT]}
      #  durations.concat(d)
      #end
      #return [uniqueContacts, nContacts, durations]
      return []
    end

  end

  class SetdestParser

    def initialize(options)
      #puts "options"
      #p options
      
      @traceFile = open(options[:tracefile]) if options.has_key?(:tracefile)
      @eventdumpFile = options[:eventdump] if options.has_key?(:eventdump)
      @offset    = nil
      @diff      = nil
      @nodes     = {}
      @contacts  = {}

      if @eventdumpFile and File.exist?(@eventdumpFile)
	open(@eventdumpFile) {|f| @events = Marshal.load(f) }
      else
	@events    = EventQueue.new
	preprocess
      end
      @events.register
      #EventDispatcher.instance.subscribe(:remTimerTick) { |t| advanceTime(t) }
    end

    private

    def preprocess
      puts "Preprocessing trace file..."
      timer = 0.0
      while timer < Config.instance.duration
	advanceTime(timer)
	timer += Config.instance.granularity
      end
      @traceFile.close
      open(@eventdumpFile, 'w') {|f| Marshal.dump(@events, f)} if @eventdumpFile
      puts "Preprocessing done."
    end

    def advanceTime(newTime)
      # Set the offset to the fist clock tick, so that we start with time = 0
      # for the parser
      #@offset = newTime.to_f unless @offset

      begin
	loop do 
	  @diff = parseLine(@traceFile.gets) unless @diff
	  if @diff
	    break if @diff[1] > newTime.to_f
	    if @diff[1] < (newTime.to_f - Config.instance.granularity)
	      puts "Error: times are not ordered (#{@diff[1]} < #{newTime})"
	    end
	    #puts "Line #{@traceFile.lineno}"
	    @nodes[@diff[0]].dest  = @diff[2]
	    @nodes[@diff[0]].speed = @diff[3]
	    @diff = nil
	  end
	end
      rescue EOFError => err
      end

      @nodes.each do |id, node|
	node.move(1)
	#node.print_pos
      end
      @nodes.each do |id1, node1| 
	@nodes.each do |id2, node2| 
	  next if id1 >= id2
	  contId = Contact.getId(node1, node2)
	  @contacts[contId] = Contact.new(node1, node2) unless @contacts[contId]
	  evType = @contacts[contId].calculateContact(newTime)
	  unless evType == :unchanged
	    @events.addEvent(newTime, node1.id, node2.id, evType)
	  end
	  #when :connect
	  #  #puts "Connect #{node1.id}, #{node2.id}"
	  #  EventDispatcher.instance.dispatch(:remConnection,node1.id,node2.id)
	  #when :disconnect
	  #  #puts "Disconnect #{node1.id}, #{node2.id}"
	  #  EventDispatcher.instance.dispatch(:remDisconnection,
	  #      			      node1.id, node2.id)
	  #end
	end
      end
    end

    INIT_PATTERN   = /\$node_\((\d+)\) set ([X|Y])_ (\d+\.\d+)$/
    MOTION_PATTERN = /\$ns_ at (\d+\.\d+) "\$node_\((\d+)\) setdest +(\d+\.\d+) (\d+\.\d+) (\d+\.\d+)"$/

    def parseLine(line)
      return nil unless line
      if INIT_PATTERN =~ line
	node = $1.to_i + 1
	axis = $2
	pos  = $3.to_f

	@nodes[node] = SetdestNode.new(node)
	if    axis == "X" then @nodes[node].x = pos
	elsif axis == "Y" then @nodes[node].y = pos
	end
      elsif MOTION_PATTERN =~ line
	time  = $1.to_i
	node  = $2.to_i + 1
	x     = $3.to_f
	y     = $4.to_f
	speed = $5.to_f

	return [node, time, [x, y], speed]
      else
	#puts "Line does not match \n#{line}"
      end
      return nil
    end

    def gatherStatistics
      #fDist = open("contacts.dat", "w")
      #fDur  = open("duration.dat", "w")

      #durations = []
      #uniqueContacts = []
      #nContacts = []
      #$nodes.each do |id, node| 
      #  ucs, ncs, dur = node.list_contacts(fDist, fDur)
      #  durations.concat(dur)
      #  uniqueContacts.push(ucs)
      #  nContacts.push(ncs)
      #end

      #durations.sort! {|d1, d2| d2[2] <=> d1[2]}
      #nContacts.sort! {|n1, n2| n2 <=> n1}
      #totalDur = durations.inject(0) {|sum, dur| sum + dur[2]}
      #totalCont= nContacts.inject {|sum, n| sum + n}
      #cumulationDur  = 0.0
      #durations.each_with_index do |entry, i| 
      #  dur = entry[2]
      #  cumulationDur += dur
      #  fDur.puts("#{i} #{entry[0]} #{entry[1]} #{dur} #{cumulationDur} #{dur.to_f/totalDur} #{cumulationDur/totalDur}")
      #end

      #cumulationCont = 0.0
      #nContacts.each_with_index do |n, i|
      #  cumulationCont += n
      #  fDist.puts("#{i} #{n} #{n.to_f/totalCont} #{cumulationCont/totalCont}")
      #end

      #fDist.close
      #fDur.close


    end

  end


end # module rem

Rem::TraceParserReg.instance.reg(:setdestParser, Rem::SetdestParser)

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

$:.unshift File.join(File.dirname(__FILE__), "..", "..", "..", "lib")
$:.unshift File.join(File.dirname(__FILE__), "..", "..")

require 'rdtnevent'
require 'eventqueue'

class SetdestNode

  attr_accessor :id, :pos, :dest, :speed

  def initialize(id)
    @id       = id
    @pos      = [0, 0]
    @dest     = [0, 0]
    @speed    = 0
    @contacts = {}
  end

  def to_s
    "#@id(#{self.object_id}): #{@pos[0]}, #{@pos[1]}"
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

  def initialize(contactDistance, node1, node2)
    @contactDistance = contactDistance
    @node1           = node1
    @node2           = node2
    @open            = false
    @times           = []
  end

  def calculateContact(time)
    diffVec = [@node1.pos[0] - @node2.pos[0], @node1.pos[1] - @node2.pos[1]]
    dist = Math.hypot(diffVec[0], diffVec[1])
    if dist <= @contactDistance
      #@contacts[node2.id] = [[$time, $time]] unless @contacts.has_key?(node2.id)
      if @open
        @times[-1][1] = time
        return :unchanged
      else
        @times.push([time, time])
        #puts "Time: #{time}"
        #puts "Dist: #{dist} #{time.to_f} (#{Config.instance.contactDistance})"
        @open = true
        return :simConnection
      end
    else
      if @open
        @open = false
        return :simDisconnection
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

  attr_reader :events

  def initialize(duration, granularity, options)
    @duration    = duration
    @granularity = granularity
    @traceFile   = open(options["tracefile"]) if options.has_key?("tracefile")
    @contactDist = options["contactDistance"] || 250
    @offset      = nil
    @diff        = nil
    @nodes       = {}
    @contacts    = {}

    @events      = Sim::EventQueue.new
    preprocess
  end

  private

  def preprocess
    puts "Preprocessing trace file..."
    timer = 0.0
    while timer < @duration
      advanceTime(timer)
      timer += @granularity
    end
    @traceFile.close
    #open(@eventdumpFile, 'w') {|f| Marshal.dump(@events, f)} if @eventdumpFile
    puts "Preprocessing done."
  end

  def advanceTime(newTime)
    # Set the offset to the fist clock tick, so that we start with time = 0
    # for the parser
    #@offset = newTime.to_f unless @offset

    begin
      loop do 
        @diff = parseLine(@traceFile.readline) unless @diff
        if @diff
          break if @diff[1] > newTime.to_f
          if @diff[1] < (newTime.to_f - @granularity)
            rerror(self, "Error: times are not ordered (#{@diff[1]} < #{newTime})")
          end
          rdebug(self, "Line #{@traceFile.lineno}") if (@traceFile.lineno % 100) == 0
          @nodes[@diff[0]].dest  = @diff[2]
          @nodes[@diff[0]].speed = @diff[3]
          @diff = nil
        end
      end
    rescue EOFError => err
    end

    @nodes.each do |id, node|
      node.move(1)
    end
    @nodes.each do |id1, node1| 
      @nodes.each do |id2, node2| 
        next if id1 >= id2
        contId = Contact.getId(node1, node2)
        unless @contacts[contId]
          @contacts[contId] = Contact.new(@contactDist, node1, node2)
        end
        evType = @contacts[contId].calculateContact(newTime)
        unless evType == :unchanged
          @events.addEvent(newTime, node1.id, node2.id, evType)
        end
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

      @nodes[node] ||= SetdestNode.new(node)
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

end

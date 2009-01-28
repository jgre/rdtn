#!/usr/bin/env ruby
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

$:.unshift File.join(File.dirname(__FILE__), "..")
$:.unshift File.join(File.dirname(__FILE__))

require 'optparse'
require 'eventqueue'
require 'dijkstra'
require 'contacthistory'

class NetworkModel

  attr_reader :contacts, :duration

  def initialize(eq = nil)
    # Node -> List of ContactHistories involving Node
    @incidents   = {} 
    @contacts    = {} 
    @duration    = 0
    self.events  = eq if eq
  end

  def events=(eq)
    eq.each do |e|
      if [:simConnection, :simDisconnection].include? e.type
        contactEvent(e.nodeId1, e.nodeId2, e.time, e.type)
      end
    end
  end

  def contactEvent(node1, node2, time, evType)
    @duration = [@duration, time].max

    id = ContactHistory.getId(node1, node2)
    unless @contacts.has_key? id
      @contacts[id] = ContactHistory.new(id)
      (@incidents[id[0]] ||= []).push(@contacts[id])
      (@incidents[id[1]] ||= []).push(@contacts[id])
    end
    ch = @contacts[id]
    if evType == :simConnection
      ch.contactStart(time)
    elsif evType == :simDisconnection
      ch.contactEnd(time)
    end
  end

  def nodes
    @incidents.keys
  end

  def edges(node)
    @incidents[node].inject([]) {|lst, cHist| lst + cHist.contacts}
  end

  def neighbors(node, time = nil)
    if time
      et = edges(node).find_all {|edge| edge.cost == 0}
      et.map {|edge| node == edge.node1 ? edge.node2 : edge.node1}
    else
      @incidents[node].map {|ch| node == ch.node1 ? ch.node2 : ch.node1}
    end
  end

  def numberOfNodes
    @incidents.length
  end

  def numberOfContacts
    @contacts.inject(0) {|sum, keyval| sum + keyval[1].numberOfContacts }
  end

  def totalContactDuration
    @contacts.inject(0) {|sum, keyval| sum + keyval[1].totalContactDuration }
  end

  def averageContactDuration
    totalContactDuration / numberOfContacts.to_f
  end

  def uniqueContacts
    @contacts.length
  end

  def totalTheoreticalHopCount
    networkAnalysis unless @totalHopCount
    @totalHopCount
  end

  def numberOfTheoreticalPaths
    networkAnalysis unless @nPaths
    @nPaths
  end

  def totalTheoreticalDelay
    networkAnalysis unless @totalDelay
    @totalDelay
  end

  def averageTheoreticalHopCount
    totalTheoreticalHopCount / numberOfTheoreticalPaths.to_f
  end

  def averageTheoreticalDelay
    totalTheoreticalDelay / numberOfTheoreticalPaths.to_f
  end

  def clusteringCoefficient(node, time = nil)
    nbrs = neighbors(node, time)

    return 1 if nbrs.length <= 1

    pairs = nbrs.inject([]) do |lst, neighbor|
      common_nbrs = neighbors(neighbor, time).find_all {|n| nbrs.include?(n)}
      lst + common_nbrs.map {|n| [neighbor, n].sort}
    end
    2 * pairs.uniq.length / (nbrs.length * (nbrs.length - 1))
  end

  def totalClusteringCoefficient(time = nil)
    totalCC = nodes.inject(0) {|sum, node| sum+clusteringCoefficient(node,time)}
    totalCC / nodes.length.to_f
  end

  def averageDegree
    sum = nodes.inject(0) {|sum, node| sum + neighbors(node, nil).length}
    sum / nodes.length.to_f
  end

  private

  def networkAnalysis
    @nPaths = 0
    @totalHopCount = @totalDelay = 0
    # FIXME
    range = (0..0)
    step  = 1
    range.step(step) do |startTime|
      nodes.each do |node|
	distVec, path = dijkstra(self, node, startTime)
	path.delete(node)
	@totalHopCount += path.values.inject(0) {|sum, p| sum + p.length - 1}
	@totalDelay    += distVec.values.inject(0) {|sum, d| sum + d}
	@nPaths        += path.length
      end
    end
  end

end

def createModels(fname)
  events = open(fname) {|f| Marshal.load(f)}
  net    = NetworkModel.new(events)
  # TODO: traffic model

  net
end

if $0 == __FILE__
  fname = ARGV[0]
  if fname.nil? or fname.empty?
    puts "Usage: #{$0} [event_file]"
    exit 1
  end

  net = createModels(fname)
  open(fname + ".netmodel", 'w') {|f| Marshal.dump(net, f)}
  # TODO: traffic model
end

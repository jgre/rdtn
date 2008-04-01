#!/usr/bin/env ruby
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

$:.unshift File.join(File.dirname(__FILE__), "..", "..", "sim")
$:.unshift File.join(File.dirname(__FILE__))

require 'optparse'
require "eventqueue"
require "dijkstra"

class StatBundle

  attr_reader :bundleId, :dest, :src, :size, :subscribers, :created

  def initialize(dest, src, bid, size, subscribers)
    @dest        = dest
    @src         = src
    @bundleId    = bid
    @size        = size
    @subscribers = subscribers
    @delivered   = {} # Node -> time
    @created     = 0
    @incidents   = []
    @outgoing    = []
  end

  def to_s
    "Bundle (#{@bundleId}): #{@src} -> #{@dest} (#{@size} bytes)"
  end

  def print(f)
    f.puts("Created #{@created}")
    @subscribers.each do |subs|
      f.puts("Subscriber #{subs}: delivered at #{@delivered[subs]}")
    end
  end

  def sentFrom(node, time)
    @outgoing.push(node)
  end

  def receivedAt(node, time)
    @incidents.push(node)
    if node == @src
      @created = time
    end
    if @subscribers.include?(node)
      if @delivered[node]
	@delivered[node] = [@delivered[node], time].min
      else
	@delivered[node] = time
      end
    end
  end

  def nDelivered
    @delivered.length
  end

  def nSubscribed
    @subscribers.length
  end

  def nReplicas
    @incidents.uniq.length
  end

  def nTimesSent
    @outgoing.length
  end

  def deliveryDelay(dest)
    if @delivered[dest]
      @delivered[dest] - @created
    else
      nil
    end
  end

  def delays
    @delivered.values.map {|time| time - @created}
  end

  def averageDelay
    return nil if @delivered.empty?
    total = delays.inject(0) {|sum, delay| sum + delay}
    return total.to_f / @delivered.length
  end

  def maxDelay
    delays.max
  end

  def minDelay
    delays.min
  end

end

class NetworkModel

  attr_accessor :sinks
  attr_reader   :contacts, :bundles

  def initialize
    # Node -> List of ContactHistories involving Node
    @incidents   = Hash.new {|hash, id| hash[id] = []}
    @contacts    = Hash.new do |hash, id| 
      hash[id] = ContactHistory.new(id)
      @incidents[id[0]].push(hash[id])
      @incidents[id[1]].push(hash[id])
      hash[id]
    end
    @bundles     = {}
    @ctrlBundles = {}
    @sinks       = Hash.new { |hash, id| hash[id] = [] }
  end

  def contactEvent(node1, node2, fromNode, time, evType)
    if evType == :simConnection or evType == :simConnect
      @contacts[ContactHistory.getId(node1, node2)].newContact(time, fromNode)
    elsif evType == :simDisconnection or evType == :simDisconnect
      @contacts[ContactHistory.getId(node1, node2)].closedContact(time,fromNode)
    end
  end

  def sink(eid, node)
    @sinks[eid].push(node)
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
      @incidents[node].map {|ch| node == ch.nodeId1 ? ch.nodeId2 : ch.nodeId1}
    end
  end

  def bundleEvent(node1, node2, inout, bundle, time)
    @bundles[bundle.bundleId] = bundle unless @bundles[bundle.bundleId]
    if inout == :in
      @bundles[bundle.bundleId].receivedAt(node1, time)
    else
      @bundles[bundle.bundleId].sentFrom(node1, time)
    end
    if node2
      @contacts[ContactHistory.getId(node1, node2)].bundleTransmission(time, @bundles[bundle.bundleId], node1, inout)
    end
  end

  def controlBundle(node1, node2, inout, bundle, time)
    @ctrlBundles[bundle.bundleId] = bundle unless @ctrlBundles[bundle.bundleId]
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

  def numberOfBundles
    @bundles.length
  end

  def delays
    @bundles.values.inject([]) {|cat, bundle| cat + bundle.delays}
  end

  def annotatedDelays
    @bundles.values.map {|bundle| [bundle.bundleId, bundle.delays]}
  end

  def totalDelay
    delays.inject(0) {|sum, delay| sum + delay}
  end

  def averageDelay
    if delays.empty?
      0
    else
      totalDelay / delays.length.to_f
    end
  end

  def numberOfReplicas
    @bundles.values.inject(0) {|sum, bundle| sum + bundle.nReplicas}
  end

  def replicasPerBundle
    if numberOfBundles == 0
      0
    else
      numberOfReplicas / numberOfBundles.to_f
    end
  end

  def numberOfSubscribedBundles
    @bundles.values.inject(0) {|sum, bundle| sum+bundle.nSubscribed}
  end

  def numberOfDeliveredBundles
    @bundles.values.inject(0) {|sum, bundle| sum+bundle.nDelivered}
  end

  def numberOfTransmissions
    @bundles.values.inject(0) {|sum, bundle| sum + bundle.nTimesSent}
  end

  def transmissionsPerBundle
    if numberOfBundles == 0
      0
    else
      numberOfTransmissions / numberOfBundles.to_f
    end
  end

  def numberOfControlBundles
    @ctrlBundles.length
  end

  def controlOverhead
    @ctrlBundles.values.inject(0) {|sum, bundle| sum + bundle.size }
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
    #puts "HopCount #{totalTheoreticalHopCount}"
    totalTheoreticalHopCount / numberOfTheoreticalPaths.to_f
  end

  def averageTheoreticalDelay
    #puts "Delay #{totalTheoreticalDelay}"
    totalTheoreticalDelay / numberOfTheoreticalPaths.to_f
  end

  def clusteringCoefficient(node, time = nil)
    nbrs = neighbors(node, time)
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
	#puts "Time #{startTime}, Node #{node}"
	distVec, path = dijkstra(self, node, startTime)
	path.delete(node)
	@totalHopCount += path.values.inject(0) {|sum, p| sum + p.length - 1}
	@totalDelay    += distVec.values.inject(0) {|sum, d| sum + d}
	@nPaths        += path.length
      end
    end
  end

end

class RdtnStatParser

  def initialize(dir, model)
    @model = model
    @dir   = dir
  end

  def eachSubdir
    Dir.foreach(@dir) do |fn|
      filename = File.join(@dir, fn)
      unless filename=="." or filename==".." or not /kasuari(\d+)$/ =~ filename
	node = $1.to_i
	yield(filename, node)
      end
    end
  end

  def parse
    startTimes = []
    eachSubdir do |filename, node|
      open(File.join(filename, "time.stat")) {|f| startTimes.push(f.read.to_i)}
      if File.exist?(File.join(filename, "subscribe.stat"))
	open(File.join(filename, "subscribe.stat")) do |f| 
	  parseSubscribeStat(node, f)
	end
      end
    end
    # Subtract the first start time from all time outputs
    # to make them more readable
    @deltaTime = startTimes.min
    puts "Delta Time #{@deltaTime}"

    eachSubdir do |filename, node|
      if File.exist?(File.join(filename, "contact.stat"))
	open(File.join(filename, "contact.stat")) {|f| parseContactStat(node,f)}
	if File.exist?(File.join(filename, "out.stat"))
	  open(File.join(filename, "out.stat")) {|f| parseIOStat(node,:out,f)}
	end
	if File.exist?(File.join(filename, "in.stat"))
	  open(File.join(filename, "in.stat"))  {|f| parseIOStat(node,:in,f)}
	end
      end
    end
  end

  private

  CONTPATTERN = /(\d+), (contact|closed), \w+, \w*, .*, \d*, dtn:\/\/[a-zA-Z]+(\d+)\//
  IOPattern = %r{(\d+), dtn://[a-zA-Z]+(\d+)/, dtn://[a-zA-Z]+(\d+)/, (-?\d+), (\d+), (true|false)(, dtn://[a-zA-Z]+(\d+)/)?$}
  SubscrPattern = %r{(\d+), dtn:subscribe/, dtn://[a-zA-Z]+(\d+)/, (-?\d+), (\d+), (true|false)(, dtn://[a-zA-Z]+(\d+)/)?$}

  def parseIOStat(fromNode, inout, file)
    file.each_line do |line|
      if IOPattern =~ line
	time        = $1.to_i - @deltaTime
	channel     = $2.to_i
	src         = $3.to_i
	bid         = $4
	size        = $5.to_i
	foreignNode = $8.to_i if $8
	bundle = StatBundle.new(channel, src, bid, size, @model.sinks[channel])
	@model.bundleEvent(fromNode, foreignNode, inout, bundle, time)

      elsif SubscrPattern =~ line
	time        = $1.to_i - @deltaTime
	src         = $2.to_i
	bid         = $3
	size        = $4.to_i
	foreignNode = $7.to_i if $7
	bundle = StatBundle.new(nil, src, bid, size, nil)
	@model.controlBundle(fromNode, foreignNode, inout, bundle, time)
      end
    end
  end

  def parseContactStat(fromNode, file)
    file.each_line do |line|
      if CONTPATTERN =~ line
	time   = $1.to_i - @deltaTime
	state  = $2
	foreignNode = $3.to_i
	evType = if state == 'contact'
		   :simConnection
		 elsif state == 'closed'
		   :simDisconnection
		 end
	@model.contactEvent(fromNode, foreignNode, fromNode, time, evType)
      end
    end
  end

  def parseSubscribeStat(fromNode, file)
    file.each_line do |line|
      if %r{^dtn://[a-zA-Z]+(\d+)/$} =~ line
	channel = $1.to_i
	@model.sink(channel, fromNode)
      end
    end
  end

end

class EventQueueParser

  def initialize(eventQueue, model, fromNode = nil)
    @ev        = eventQueue
    @model     = model
    @fromNode  = fromNode
  end

  def parse
    @ev.events.each do |event|
      time  = event[0].to_i - @ev.deltaTime.to_i
      node1 = event[1]
      node2 = event[2]
      state = event[3]
      @model.contactEvent(node1, node2, @fromNode, time, state)
    end
  end

end

class SummaryReport

  def initialize(model)
    @model = model
  end

  def printGlobalInformation(file)
    file.puts("#{@model.numberOfContacts} contacts")
    file.puts("#{@model.uniqueContacts} contacts between unique pairs of nodes")
    file.puts("#{@model.averageContactDuration} avarage contact duration")
    file.puts("#{@model.numberOfBundles} bundles created")
    file.puts("#{@model.numberOfSubscribedBundles} bundles subscribed")
    file.puts("#{@model.numberOfDeliveredBundles} bundles delivered (#{(@model.numberOfDeliveredBundles.to_f / @model.numberOfSubscribedBundles) * 100}%)")
    file.puts("#{@model.numberOfReplicas} replicas")
    file.puts("#{@model.replicasPerBundle} replicas per bundle")
    file.puts("#{@model.numberOfTransmissions} bundle transmissions")
    file.puts("#{@model.transmissionsPerBundle} transmissions per bundle")
    file.puts("#{@model.averageDelay} seconds avarage delay")
    file.puts("#{@model.numberOfControlBundles} subscription bundles (#{@model.controlOverhead} bytes)")
    file.puts
    file.puts("#{@model.totalClusteringCoefficient} clustering coefficient")
    file.puts("#{@model.averageDegree} average degree")
    file.puts("#{@model.averageTheoreticalHopCount} average theoretical hop count")
  end

  def printContacts(dirName)
    @model.contacts.each_value do |contHist|
      open(File.join(dirName, "contact#{contHist.id}.stat"), "w") do |file|
        contHist.print(file)
        file.puts
        file.puts
      end
    end
  end

  def printGraphviz(dirName)
    open(File.join(dirName,"contactgraph.dot"),"w") do |f|
      f.puts("graph contactgraph {")
      @model.contacts.each_value do |contHist|
        f.puts("#{contHist.nodeId1} -- #{contHist.nodeId2}")
      end
      f.puts("}")
    end
    system("dot -Tpng " + File.join(dirName,"contactgraph.dot") + "> " + File.join(dirName,"contactgraph.png"))

    @model.bundles.each do |bundleId, bundle|
      bundleName = "bundle#{bundle.dest}_#{bundleId}".sub("-", "_")
      open(File.join(dirName,"#{bundleName}.stat"),"w") do |f|
        f.puts(bundle.to_s)
        bundle.print(f)
        f.puts
      end
      open(File.join(dirName,"#{bundleName}.dot"),"w") do |f|
        f.puts("digraph #{bundleName} {")
        @contacts.each_value do |contHist|
          contHist.printGraphviz(f, bundleId)
        end
        f.puts("}")
      end
      system("dot -Tpng " + File.join(dirName,"#{bundleName}.dot") + "> " + File.join(dirName,"#{bundleName}.png"))
    end
  end

  #def checkContacts
  #  @contacts.each_value do |contHist|
  #    missing = contHist.checkContacts
  #    if missing
  #      Strangeness.missedContacts(contHist, missing[0], missing[1])
  #    end
  #  end
  #end

  #def checkTransmissions
  #  @contacts.each_value do |contHist|
  #    contHist.checkTransmissions
  #  end
  #end

end

class PathReport

  def initialize(model)
    @model = model
  end

  def printPathReport(file)
    @model.bundles.values.each do |bundle|
      file.puts("#{bundle}, created #{bundle.created}")
      distVec, path = dijkstra(@model, bundle.src, bundle.created)
      bundle.subscribers.each do |subs|
	file.puts("Delivered to #{subs} after #{bundle.deliveryDelay(subs)} sec (ideally: #{distVec[subs]} sec: [#{path[subs].join(', ')}])")
      end
      file.puts
    end
  end

end

class NetworkAnalysisReport

  def initialize(model)
    @model = model
  end

  def printNetworkAnalysis(file, range, step)
    file.puts("Calculated #{@model.numberOfTheoreticalPaths} paths")
    file.puts("Average path length: #{@model.averageTheoreticalHopCount} hops")
    file.puts("Average delay: #{@model.averageTheoreticalDelay} sec")
  end

end

class ContactHistory

  attr_reader :id, :nodeId1, :nodeId2

  def initialize(id)
    @id = id
    @nodeId1  = id[0]
    @nodeId2  = id[1]
    @contacts = {}
    @contacts[@nodeId1] = []
    @contacts[@nodeId2] = []
    @contacts[nil]      = []
  end

  def ContactHistory.getId(nodeId1, nodeId2)
    [nodeId1, nodeId2].sort
  end

  def newContact(time, node)
    n1 = node ? node : @nodeId1
    otherNode = n1 == @nodeId1 ? @nodeId2 : @nodeId1
    if @contacts[node][-1] and @contacts[node][-1].open?
      #Strangeness.unfinishedContact(n1, otherNode, 
      #				    @contacts[node][-1].startTime, time)
      @contacts[node].pop # Delete the unfinished contact as it only messes up our calculation
    end
    @contacts[node].push(Contact.new(n1, otherNode, time))
  end

  def closedContact(time, node)
    otherNode = node == @nodeId1 ? @nodeId2 : @nodeId1
    if not @contacts[node][-1]
      #Strangeness.doubleEndedContact(node, otherNode, nil, time)
    else
      @contacts[node][-1].endContact(time)
    end
  end

  def bundleTransmission(time, bundle, node, inout)
    contact = @contacts[node].find do |cont|
      cont.startTime <= time and (cont.open? or time <= cont.endTime)
    end
    if contact
      contact.bundleTransmission(time, bundle, inout)
    else
      otherNode = node == @nodeId1 ? @nodeId2 : @nodeId1
      #Strangeness.contactlessTransmission(time, bundle, node, otherNode)
    end
  end

  def print(file)
    file.puts("#{@nodeId1} -> #{@nodeId2}: #{@contacts[@nodeId1].length} contacts seen")
    file.puts("#{@nodeId2} -> #{@nodeId1}: #{@contacts[@nodeId2].length} contacts seen")
    file.puts("#{@nodeId2} <-> #{@nodeId1} (EventQueue): #{@contacts[nil].length} contacts sent") if @contacts[nil]
    file.puts
    lengths = @contacts.map {|id, cont| cont.length}
    lengths.max.times do |i|
      if @contacts[@nodeId1][i] then str1 = @contacts[@nodeId1][i].to_s
      else str1 = " " * 15
      end
      if @contacts[@nodeId2][i] then str2 = @contacts[@nodeId2][i].to_s
      else str2 = " " * 15
      end
      if @contacts[nil] and @contacts[nil][i] then str3 = @contacts[nil][i].to_s
      else str3 = " " * 15
      end
      file.puts("#{str1} / #{str2} / EQ: #{str3}")
    end
  end

  #def checkContacts
  #  return nil if @contacts[nil].length == @contacts[@nodeId1].length and @contacts[nil].length == @contacts[@nodeId2].length
  #  missingIn1 = missingIn2 = []
  #  @contacts[nil].each_with_index do |cont0, i|
  #    cont1 = @contacts[@nodeId1][i]
  #    cont2 = @contacts[@nodeId2][i]
  #    if cont1
  #      diffCur  = cont0.difference(cont1)
  #      if @contacts[nil][i+1]
  #        diffNext = @contacts[nil][i+1].difference(cont1)
  #        if diffNext < diffCur 
  #          missingIn1.push(cont0)
  #        end
  #      end
  #    else
  #      missingIn1.push(cont0)
  #    end
  #    if cont2
  #      diffCur  = cont0.difference(cont2)
  #      if @contacts[nil][i+1]
  #        diffNext = @contacts[nil][i+1].difference(cont2)
  #        if diffNext < diffCur 
  #          missingIn2.push(cont0)
  #        end
  #      end
  #    else
  #      missingIn2.push(cont0)
  #    end
  #  end
  #  return nil if missingIn1.empty? and missingIn2.empty?
  #  return [missingIn1, missingIn2]
  #end

  #def checkTransmissions
  #  @contacts[@nodeId1].each_with_index do |cont1, i|
  #    cont2 = @contacts[@nodeId2][i]
  #    cont1.checkTransmissions(cont2)
  #  end
  #  @contacts[@nodeId2].each_with_index do |cont2, i|
  #    cont1 = @contacts[@nodeId1][i]
  #    cont2.checkTransmissions(cont1)
  #  end
  #end

  def printGraphviz(file, bundleId)
    @contacts[@nodeId1].each_with_index do |cont1, i|
      cont2 = @contacts[@nodeId2][i]
      cont1.printGraphviz(file, bundleId, cont2)
    end
    @contacts[@nodeId2].each_with_index do |cont2, i|
      cont1 = @contacts[@nodeId1][i]
      cont2.printGraphviz(file, bundleId, cont1)
    end
  end

  #def correspondingContacts
  #  ret = []
  #  clone1 = @contacts[@nodeId1].clone
  #  clone2 = @contacts[@nodeId2].clone
  #  endTimes = (clone1 + clone2).map {|c| c.endTime}
  #  endTimes.delete(nil)
  #  maxTime = 1
  #  maxTime = endTimes.max + 1 unless endTimes.empty?
  #  prevEndN1 = prevEndN2 = 0
  #  nextStartN1 = nextStartN2 = maxTime
  #  until clone1.empty? or clone2.empty?
  #    if clone1[1] then nextStartN1 = clone1[1].startTime 
  #    else nextStartN1 = maxTime
  #    end
  #    if clone2[1] then nextStartN2 = clone2[1].startTime 
  #    else nextStartN2 = maxTime
  #    end
  #    curMatch = [nil, nil]
  #    #puts
  #    #puts "#{prevEndN1} #{prevEndN2}"
  #    #puts "#{clone1[0].startTime} #{clone2[0].startTime}"
  #    #puts "#{clone1[0].endTime} #{clone2[0].endTime}"
  #    #puts "#{nextStartN1} #{nextStartN2}"
  #    #puts
  #    if (not clone1[0].endTime or clone1[0].endTime <= nextStartN2)
  #      prevEndN1 = clone1[0].endTime if clone1[0].endTime
  #      curMatch[0] = clone1.shift
  #    end
  #    if (not clone2[0].endTime or clone2[0].endTime <= nextStartN1)
  #      prevEndN2 = clone2[0].endTime if clone2[0].endTime
  #      curMatch[1] = clone2.shift
  #    end
  #    #if clone1[0].startTime > prevEndN2 and (not clone1[0].endTime or clone1[0].endTime < nextStartN2)
  #    #  prevEndN1 = clone1[0].endTime if clone1[0].endTime
  #    #  curMatch[0] = clone1.shift
  #    #end
  #    #if clone2[0].startTime > prevEndN1 and (not clone2[0].endTime or clone2[0].endTime < nextStartN1)
  #    #  prevEndN2 = clone2[0].endTime if clone2[0].endTime
  #    #  curMatch[1] = clone2.shift
  #    #end
  #    if curMatch[0] and curMatch[1]
  #      ret.push(curMatch)
  #    else
  #      if curMatch[0] 
  #        seeingNode = @nodeId1 
  #        blindNode = @nodeId2
  #        prevEndBN = prevEndN2
  #        nextStartBN = nextStartN2
  #        cont = curMatch[0]
  #      elsif curMatch[1]
  #        seeingNode = @nodeId2
  #        blindNode = @nodeId1
  #        prevEndBN = prevEndN1
  #        nextStartBN = nextStartN1
  #        cont = curMatch[1]
  #      else 
  #        raise RuntimeError, "Overlapping Contacts (#{clone1[0].startTime} - #{clone1[0].endTime}, #{clone2[0].startTime} - #{clone2[0].endTime})"
  #      end
  #      #Strangeness.unmatchedContact(seeingNode, blindNode, cont.startTime,
  #      #			     cont.endTime, prevEndBN, nextStartBN)
  #    end
  #  end
  #  unmatchedContacts = []
  #  if not clone1.empty?
  #    seeingNode = @nodeId1
  #    blindNode  = @nodeId2
  #    unmachtedContacts = clone1
  #  elsif not clone2.empty?
  #    seeingNode = @nodeId2
  #    blindNode  = @nodeId1
  #    unmatchedContacts = clone2
  #  end
  #  unmatchedContacts.each do |cont|
  #    #Strangeness.unmatchedContact(seeingNode, blindNode, cont.startTime,
  #    #				   cont.endTime, nil, nil)
  #  end
  #  return ret
  #end

  def numberOfContacts
    if @contacts[@nodeId1].empty?
      @contacts[nil].length
    else
      @contacts[@nodeId1].length
    end
  end

  def totalContactDuration
    if @contacts[@nodeId1].empty?
      @contacts[nil].inject(0) { |sum, cont| sum + cont.duration }
    else
      @contacts[@nodeId1].inject(0) { |sum, cont| sum + cont.duration }
    end
  end

  def contacts
    if @contacts[@nodeId1].empty?
      @contacts[nil]
    else
      @contacts[@nodeId1]
    end
  end

end

class Contact

  attr_accessor :startTime, :endTime
  attr_reader   :node1, :node2, :time, :inbundles, :outbundles

  def initialize(node1, node2, startTime)
    @node1   = node1
    @node2   = node2
    @startTime = startTime
    @inbundles = {} # BundleId -> Time
    @outbundles= {} # BundleId -> Time
  end

  def endContact(time)
    unless open?
      #Strangeness.doubleEndedContact(@node1, @node2, @endTime, time)
    end
    @endTime = time
  end

  def open?
    @startTime and not @endTime
  end

  def duration
    return 0 if open?
    @endTime - @startTime
  end

  def to_s
    "#{@node1} -> #{@node2}: #{@startTime} - #{@endTime}"
  end

  def difference(cont2)
    diffStart = (@startTime - cont2.startTime).abs
    e1 = @endTime ? @endTime : 0
    e2 = cont2.endTime ? cont2.endTime : 0
    diffEnd   = (e1 - e2).abs
    (diffStart + diffEnd) / 2.0
  end

  def bundleTransmission(time, bundle, inout)
    if inout == :in
      @inbundles[bundle.bundleId] = time
    else
      @outbundles[bundle.bundleId] = time
    end
  end

  def bundleSent?(bundleId, time)
    @outbundles[bundleId] # and @outbundles[bundleId] <= time
  end

  def bundleReceived?(bundleId, time)
    @inbundles[bundleId] # and @inbundles[bundleId] <= time
  end

  def checkTransmissions(cont2)
    @outbundles.each do |bundleId, time|
      unless cont2 and cont2.bundleReceived?(bundleId, time)
	#puts "sentOnly(#{@node1}, #{@node2}, #{bundleId}, #{time})"
	#Strangeness.sentOnly(@node1, @node2, bundleId, time)
      end
    end
    @inbundles.each do |bundleId, time|
      unless cont2 and cont2.bundleSent?(bundleId, time)
	puts "receivedOnly(#{@node1}, #{@node2}, #{bundleId}, #{time})"
	#Strangeness.receivedOnly(@node1, @node2, bundleId, time)
      end
    end
  end

  def printGraphviz(file, bundleId, cont2)
    time = @outbundles[bundleId]
    if time and cont2 and cont2.bundleReceived?(bundleId, time)
      file.puts("#{@node1} -> #{@node2} [label=\"#{time}\"];")
    end
  end

  def cost(time)
    if time < @startTime
      @startTime - time
    elsif @endTime.nil? or time <= @endTime
      0
    else
      nil
    end
  end

end

def evalRun(dirName)
  model = NetworkModel.new

  if File.exist?(File.join(dirName, "eventdump"))
    evQ = open(File.join(dirName, "eventdump")) {|f| Marshal.load(f)}
    EventQueueParser.new(evQ, model).parse
  end

  RdtnStatParser.new(dirName, model).parse

  model
end

if $0 == __FILE__
  genGraphviz = genContactStats = pathReport = analysis = false
  opts = OptionParser.new
  opts.on("-g", "--graphviz", "Generate Graphviz files") {genGraphviz = true}
  opts.on("-c", "--contstats", "Generate Contact stats") {genContactStats=true}
  opts.on("-p", "--path", "Generate path report") {pathReport=true}
  opts.on("-a", "--analyze", "Print network analysis") {analysis=true}
  rest = opts.parse(ARGV)

  if rest.empty?
    dirName = Dir.getwd
  else
    dirName = File.expand_path(rest)
  end

  model = evalRun(dirName)
  report = SummaryReport.new(model)
  open(File.join(dirName, "global.stat"), "w") do |file|
    report.printGlobalInformation(file)
  end
  report.printContacts(dirName) if genContactStats
  report.printGraphviz(dirName) if genGraphviz
  if pathReport
    pr = PathReport.new(model)
    open(File.join(dirName, "path.stats"), "w") {|f| pr.printPathReport(f) }
  end
  if analysis
    netan = NetworkAnalysisReport.new(model)
    open(File.join(dirName, "analysis.stats"), "w") do |f| 
      netan.printNetworkAnalysis(f, (0..1000), 100)
    end
  end

elsif $0 == "irb"
  $model = evalRun(Dir.getwd)
end


$:.unshift File.join(File.dirname(__FILE__), "..")
$:.unshift File.join(File.dirname(__FILE__))

require 'statbundle'
require 'core'
require 'networkmodel'
require 'memoize'

Struct.new('Registration', :node, :startTime, :endTime)

def ruby_version_geq(target)
  tg  = []
  cur = []
  if /(\d+)\.(\d+).(\d+)/ =~ target
    tg = [$1, $2, $3]
  end
  if /(\d+)\.(\d+).(\d+)/ =~ RUBY_VERSION
    cur = [$1, $2, $3]
  end
  tg.each_with_index {|val, i| return false unless cur[i].to_i >= val.to_i}
  true
end

unless ruby_version_geq("1.8.7")
  class Array
    def find_index(obj)
      self.each_with_index {|entry, i| return i if entry == obj}
    end
  end
end

class TrafficModel

  extend Memoize

  def initialize(t0, log = nil)
    @t0        = t0
    @bundles   = {} # bundleId -> StatBundle
    @regs      = Hash.new {|hash, key| hash[key] = []}
    # node -> list of buffer use samples [time, buffer size]
    @bufferUse = Hash.new {|hash, key| hash[key] = []}
    @duration  = 0
    @errors    = []
    self.log   = log if log
  end

  def log=(log)
    log.each {|e| event e}
  end

  def event(e)
    @duration = [@duration, e.time].max
    case e.eventId
    when :bundleCreated
      @bundles[e.bundle.bundleId] = StatBundle.new(@t0, e.bundle)
    when :bundleForwarded
      @bundles[e.bundle.bundleId] = StatBundle.new(@t0, e.bundle) unless @bundles[e.bundle.bundleId]
      @bundles[e.bundle.bundleId].forwarded(e.time, e.nodeId1, e.nodeId2)
    when :registered
      @regs[e.eid] << Struct::Registration.new(e.nodeId1, e.time)
    when :unregistered
      reg = @regs[e.eid].find {|r| r.node == e.nodeId1}
      reg.endTime = e.time if reg
    when :bundleStored
      lastEntry = @bufferUse[e.nodeId1].last
      lastSize  = lastEntry.nil? ? 0 : lastEntry[1]
      @bufferUse[e.nodeId1] << [e.time, lastSize + e.bundle.payload.bytesize]
    when :bundleRemoved
      lastEntry = @bufferUse[e.nodeId1].last
      lastSize  = lastEntry.nil? ? 0 : lastEntry[1]
      @bufferUse[e.nodeId1] << [e.time, lastSize - e.bundle.payload.bytesize]
    when :transmissionError
      @bundles[e.bundle.bundleId] = StatBundle.new(@t0, e.bundle) unless @bundles[e.bundle.bundleId]
      @errors << [e.transmitted, e.bundle.bundleId]
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

  def regularBundles
    @bundles.values.find_all {|b| !b.signaling?}
  end

  def numberOfBundles
    regularBundles.length
  end

  def delays(considerReg = false)
    @bundles.values.inject([]) do |cat, bundle|
      cat + bundle.delays(@regs[bundle.dest], considerReg)
    end
  end

  def annotatedDelays
    @bundles.values.map {|bundle| [bundle.bundleId, bundle.delays]}
  end

  def totalDelay(considerReg = false)
    delays(considerReg).inject(0) {|sum, delay| sum + delay}
  end

  def averageDelay(considerReg = false)
    if delays.empty?
      0
    else
      totalDelay(considerReg) / delays.length.to_f
    end
  end

  def medianDelay(considerReg = false)
    if delays.empty?
      0
    else
      delays(considerReg).sort[delays.length / 2]
    end
  end

  def numberOfReplicas(bundle = nil)
    lst = bundle.nil? ? @bundles.values : [@bundles[bundle.bundleId]].compact
    lst.inject(0) {|sum, bundle| sum + bundle.nReplicas}
  end

  def replicasPerBundle
    if numberOfBundles == 0
      0
    else
      numberOfReplicas / numberOfBundles.to_f
    end
  end

  def memo_dijkstra(graph, src, time)
    dijkstra(graph, src, time)
  end
  remember :memo_dijkstra

  def channel_content(channel)
    @bundles.values.find_all {|b| b.dest == channel}.sort_by {|b| b.created}
  end
  remember :channel_content

  def numberOfExpectedBundles(options = {})
    net   = options[:net]
    quota = options[:quota]

    def reg_before_expiry?(b, reg)
      b.expires.nil? or b.expires > reg.startTime
    end
    def created_during_reg?(b, reg)
      reg.endTime.nil? or b.created.to_i < reg.endTime
    end
    def reachable_during_life?(b, reg, dists)
      (dists.nil? or (dists[reg.node] and (b.lifetime.nil? or dists[reg.node] < b.lifetime)))
    end
    def reachable_during_reg?(b, reg, dists)
      (dists.nil? or reg.endTime.nil? or
       (dists[reg.node] and dists[reg.node] < (reg.endTime - b.created.to_i)))
    end
    def bundle_currency_interval(b, quota)
      content       = channel_content(b.dest)
      superseded_by = content[content.find_index(b)+quota]
      [b.created, superseded_by ? superseded_by.created : nil]
    end
    def in_quota?(b, reg, quota, sampling_rate = 3600)
      int = bundle_currency_interval(b, quota)
      (reg.endTime.nil? or reg.endTime > int[0]) and (int[1].nil? or reg.startTime < int[1])
    end

    regularBundles.inject(0) do |sum, bundle|
      dists, paths = memo_dijkstra(net, bundle.src, bundle.created.to_i) if net
      dests = (@regs[bundle.dest] || []).find_all do |reg|
	if quota
	  in_quota?(bundle, reg, quota)
	else
	  (reg_before_expiry?(bundle, reg) and created_during_reg?(bundle,reg) and
	   reachable_during_life?(bundle, reg, dists) and
	   reachable_during_reg?(bundle, reg, dists))
	end
      end
      sum + (bundle.multicast? ? dests.length : 1)
    end
  end
  remember :numberOfExpectedBundles

  def numberOfDeliveredBundles
    regularBundles.inject(0) {|sum, b| sum + b.nDelivered(@regs[b.dest])}
  end

  def deliveryRatio(options = {})
    numberOfDeliveredBundles / numberOfExpectedBundles(options).to_f
  end

  def numberOfTransmissions(options = {})
    bundleLst = options[:ignoreSignaling] ? regularBundles : @bundles.values
    bundleLst.inject(0) {|sum, bundle| sum + bundle.transmissions}
  end

  def bytesTransmitted(options = {})
    bundleLst = options[:ignoreSignaling] ? regularBundles : @bundles.values
    bundleLst.inject(0) {|sum, b| sum + b.transmissions * b.payload_size}
  end

  def transmissionsPerBundle
    if numberOfBundles == 0
      0
    else
      numberOfTransmissions / numberOfBundles.to_f
    end
  end

  def signalingBundles
    @bundles.values.find_all {|b| b.signaling?}
  end

  def numberOfSignalingBundles
    signalingBundles.length
  end

  def bufferUse(samplingRate, node = nil)
    if node.nil?
      @bufferUse.keys.inject([]) {|memo,node| memo+bufferUse(samplingRate,node)}
    else
      ret      = []
      i        = 0
      if @bufferUse[node]
	uses     = @bufferUse[node].sort_by {|time, size| time}
	samplingRate.step(@duration, samplingRate) do |time|
	  until uses[i].nil? or uses[i][0] > time; i += 1; end
	  ret << uses[i-1][1]
	end
      end
      ret
    end
  end

  def numberOfTransmissionErrors(options = {})
    failedTransmissions(options).length
  end


  def failedTransmissions(options = {})
    filtered = @errors.find_all do |transmitted, bundleId|
      !(options[:ignoreSignaling] && @bundles[bundleId].signaling?)
    end
    filtered.map {|transmitted, bundleId| transmitted}
  end

  def failedTransmissionVolume(options = {})
    failedTransmissions(options).inject {|sum, error| sum + error}
  end

  def marshal_dump
    [@t0, @bundles, Hash.new.merge(@regs), @duration,Hash.new.merge(@bufferUse), @errors]
  end

  def marshal_load(lst)
    @t0, @bundles, @regs, @duration, @bufferUse, @errors = lst
  end

  def to_yaml_properties
    @regs = Hash.new.merge(@regs)
    @bufferUse = Hash.new.merge(@bufferUse)
    %w{@t0 @bundles @regs @duration @bufferUse @errors}
  end

end

$:.unshift File.join(File.dirname(__FILE__), "..")
$:.unshift File.join(File.dirname(__FILE__))

require 'statbundle'
require 'core'
require 'networkmodel'
require 'memoize'

Struct.new('Registration', :node, :startTime, :endTime)

class TrafficModel

  extend Memoize

  def initialize(t0, log = nil)
    @t0       = t0
    @bundles  = {} # bundleId -> StatBundle
    @regs     = Hash.new {|hash, key| hash[key] = []}
    @duration = 0
    self.log  = log if log
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
      @bundles[e.bundle.bundleId].forwarded(e.time, e.nodeId1, e.nodeId2)
    when :registered
      @regs[e.eid] << Struct::Registration.new(e.nodeId1, e.time)
    when :unregistered
      reg = @regs[e.eid].find {|r| r.node == e.nodeId1}
      reg.endTime = e.time if reg
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

  def delays
    @bundles.values.inject([]) do |cat, bundle|
      cat + bundle.delays(@regs[bundle.dest])
    end
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

  def numberOfTransmissions
    regularBundles.inject(0) {|sum, bundle| sum + bundle.transmissions}
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

  def marshal_dump
    [@t0, @bundles, Hash.new.merge(@regs)]
  end

  def marshal_load(lst)
    @t0, @bundles, @regs = lst
  end

  def to_yaml_properties
    @regs = Hash.new.merge(@regs)
    %w{@t0 @bundles @regs @duration}
  end

end

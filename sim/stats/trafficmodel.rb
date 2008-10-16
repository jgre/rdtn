$:.unshift File.join(File.dirname(__FILE__), "..")
$:.unshift File.join(File.dirname(__FILE__))

require 'statbundle'
require 'core'
require 'networkmodel'
require 'memoize'

Struct.new('Registration', :node, :startTime, :endTime)

class TrafficModel

  extend Memoize

  def initialize(t0, log)
    @t0      = t0
    @bundles = {} # bundleId -> StatBundle
    @regs    = Hash.new {|hash, key| hash[key] = []}
    self.log = log
  end

  def log=(log)
    log.each do |e|
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

  remember :memo_dijkstra do |graph, src, time|
    dijkstra(graph, src, time)
  end

  def numberOfExpectedBundles(net = nil)
    def reg_before_expiry?(b, reg)
      b.expires > reg.startTime
    end
    def created_during_reg?(b, reg)
      reg.endTime.nil? or b.created.to_i < reg.endTime
    end
    def reachable_during_life?(b, reg, dists)
      (dists.nil? or (dists[reg.node] and dists[reg.node] < b.lifetime))
    end
    def reachable_during_reg?(b, reg, dists)
      (dists.nil? or reg.endTime.nil? or
       (dists[reg.node] and dists[reg.node] < (reg.endTime - b.created.to_i)))
    end

    regularBundles.inject(0) do |sum, bundle|
      dists, paths = memo_dijkstra(net, bundle.src, bundle.created.to_i) if net
      dests = @regs[bundle.dest].find_all do |reg|
	(reg_before_expiry?(bundle, reg) and created_during_reg?(bundle,reg) and
	 reachable_during_life?(bundle, reg, dists) and
	 reachable_during_reg?(bundle, reg, dists))
      end
      sum + (bundle.multicast? ? dests.length : 1)
    end
  end

  def numberOfDeliveredBundles
    regularBundles.inject(0) {|sum, b| sum + b.nDelivered(@regs[b.dest])}
  end

  def deliveryRatio(net = nil)
    numberOfDeliveredBundles / numberOfExpectedBundles(net).to_f
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
    %w{@t0 @bundles @regs}
  end

end

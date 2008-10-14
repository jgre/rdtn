$:.unshift File.join(File.dirname(__FILE__), "..")
$:.unshift File.join(File.dirname(__FILE__))

require 'statbundle'
require 'core'
require 'networkmodel'

Struct.new('Registration', :node, :startTime, :endTime)

class TrafficModel

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
        reg = @regs[e.eid].find {|r| r.node = e.nodeId1}
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

  def numberOfExpectedBundles(net = nil)
    regularBundles.inject(0) do |sum, bundle|
      dists, paths = dijkstra(net, bundle.src, bundle.created.to_i) if net
      dests = @regs[bundle.dest].find_all do |n|
	bundle.expires > n.startTime and (n.endTime.nil? or bundle.created.to_i < n.endTime) and (dists.nil? or (dists[n.node] and dists[n.node] < bundle.lifetime))
      end
      sum + (bundle.multicast? ? dests.length : 1)
    end
  end

  def numberOfDeliveredBundles
    regularBundles.inject(0) do |sum, b|
      sum + b.nDelivered(((@regs[b.dest].map(&:node) || []) + [b.dest]).uniq)
    end
  end

  def deliveryRatio
    numberOfDeliveredBundles / numberOfExpectedBundles.to_f
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

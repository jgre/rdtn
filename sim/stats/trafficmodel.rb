$:.unshift File.join(File.dirname(__FILE__), "..")
$:.unshift File.join(File.dirname(__FILE__))

require 'statbundle'
require 'core'

class TrafficModel

  def initialize(t0, log)
    @t0      = t0
    @bundles = {} # bundleId -> StatBundle
    self.log = log
  end

  def log=(log)
    log.each do |e|
      case e.eventId
      when :bundleCreated
        @bundles[e.bundle.bundleId] = StatBundle.new(@t0, e.bundle)
      when :bundleForwarded
        @bundles[e.bundle.bundleId].forwarded(e.time, e.nodeId1, e.nodeId2)
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

  def controlBundle(node1, node2, inout, bundle, time)
    @ctrlBundles[bundle.bundleId] = bundle unless @ctrlBundles[bundle.bundleId]
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

  def deliveryRatio
    numberOfDeliveredBundles / numberOfBundles.to_f
  end

  def numberOfTransmissions
    @bundles.values.inject(0) {|sum, bundle| sum + bundle.transmissions}
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

end

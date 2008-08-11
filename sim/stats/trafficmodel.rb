
$:.unshift File.join(File.dirname(__FILE__), "..")
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

class TrafficModel

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

end

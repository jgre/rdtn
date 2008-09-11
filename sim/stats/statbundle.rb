$:.unshift File.join(File.dirname(__FILE__), "..")
$:.unshift File.join(File.dirname(__FILE__))

class StatBundle

  attr_reader :bundleId, :dest, :src, :payload_size, :subscribers, :created,
    :transmissions

  def initialize(t0, bundle)
    @bundleId     = bundle.bundleId
    @dest         = $1.to_i if %r{dtn://kasuari(\d+)/?} =~ bundle.destEid.to_s
    @src          = $1.to_i if %r{dtn://kasuari(\d+)/?} =~ bundle.srcEid.to_s
    @payload_size = bundle.payload.length
    @created      = bundle.created - t0.to_i

    @transmissions = 0
    @incidents     = Hash.new {|hash, key| hash[key] = []} # Node->list of times
  end

  def to_s
    "Bundle (#{@bundleId}): #{@src} -> #{@dest} (#{@payload_size} bytes)"
  end

  def forwarded(time, sender, receiver)
    @transmissions += 1  
    @incidents[receiver].push(time)
  end

  def delivered?
    @incidents.has_key? @dest
  end

  def nDelivered
    delivered? ? 1 : 0
  end

  def nReplicas
    @incidents.length
  end

  def delays
    if delivered?
      [@incidents[dest].min - @created.to_i]
    else
      []
    end
  end

  def averageDelay
    return nil unless delivered?
    delays.inject(0) {|sum, delay| sum + delay}
    # FIXME multicast
  end

  def maxDelay
    delays.max
  end

  def minDelay
    delays.min
  end

end

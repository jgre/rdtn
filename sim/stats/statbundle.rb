$:.unshift File.join(File.dirname(__FILE__), "..")
$:.unshift File.join(File.dirname(__FILE__))

class StatBundle

  attr_reader :bundleId, :dest, :src, :payload_size, :created,
    :lifetime, :transmissions, :multicast, :signaling
  attr_reader :incidents

  def initialize(t0, bundle)
    @bundleId     = bundle.bundleId
    if %r{dtn://kasuari(\d+)/?} =~ bundle.destEid
      @dest       = $1.to_i
    else
      @dest       = bundle.destEid
    end
    @src          = $1.to_i if %r{dtn://kasuari(\d+)/?} =~ bundle.srcEid.to_s
    @payload_size = bundle.payload.length
    @created      = bundle.created.to_i - t0.to_i
    @lifetime     = bundle.lifetime
    @multicast    = !bundle.destinationIsSingleton?
    @signaling    = bundle.isVaccination?

    @transmissions = 0
    @incidents     = Hash.new {|hash, key| hash[key] = []} # Node->list of times
  end

  alias signaling? signaling

  def to_s
    "Bundle (#{@bundleId}): #{@src} -> #{@dest} (#{@payload_size} bytes)"
  end

  alias multicast? multicast

  def expires
    @lifetime.nil? ? nil : @created.to_i + @lifetime.to_i
  end

  def forwarded(time, sender, receiver)
    @transmissions += 1  
    @incidents[receiver].push(time)
  end

  def delivered?(reg = nil)
    if reg.nil?
      @incidents.has_key? @dest
    else
      @incidents.has_key?(reg.node) and (expires.nil? or reg.startTime < expires) and (reg.endTime.nil? or reg.endTime > @created)
    end
  end

  def nDelivered(regs = nil)
    regs = [Struct::Registration.new(@dest, 0)] if regs.nil? or regs.empty?
    regs.inject(0) {|sum, reg| sum + (delivered?(reg) ? 1 : 0)}
  end

  def nReplicas
    @incidents.length
  end

  def delays(regs = nil)
    regs = [Struct::Registration.new(@dest, 0)] if regs.nil? or regs.empty?
    ret = regs.map do |reg|
      @incidents[reg.node].min - @created.to_i if delivered?(reg)
    end
    ret.compact
  end

  #def averageDelay
  #  return nil unless delivered?
  #  delays.inject(0) {|sum, delay| sum + delay}
  #  # FIXME multicast
  #end

  def maxDelay
    delays.max
  end

  def minDelay
    delays.min
  end

  def to_yaml_properties
    @incidents = Hash.new.merge(@incidents) if @incidents
    %w{@bundleId @dest @src @payload_size @created @lifetime @multicast
    @transmissions @incidents @signaling}
  end

end

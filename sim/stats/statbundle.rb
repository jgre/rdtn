$:.unshift File.join(File.dirname(__FILE__), "..")
$:.unshift File.join(File.dirname(__FILE__), "../../lib")
$:.unshift File.join(File.dirname(__FILE__))

require 'dpsp'

class StatBundle

  attr_reader :bundleId, :dest, :src, :payload_size, :created,
    :lifetime, :transmissions, :multicast, :signaling
  attr_reader :incidents

  def initialize(t0, bundle)
    @bundleId     = bundle.bundleId
    if %r{dtn://kasuari(\d+)/?} =~ bundle.destEid
      @dest       = $1.to_i
    elsif %r{dtn://kasuari(\w+)/?} =~ bundle.destEid
      @dest       = $1
    else
      @dest       = bundle.destEid
    end
    if %r{dtn://kasuari(\d+)/?} =~ bundle.srcEid.to_s
      @src        = $1.to_i
    elsif %r{dtn://kasuari(\w+)/?} =~ bundle.srcEid.to_s
      @src        = $1
    else
      @src        = bundle.srcEid.to_s
    end
    @payload_size = bundle.payloadLength
    @created      = bundle.created.to_i - t0.to_i
    @lifetime     = bundle.lifetime
    @multicast    = !bundle.destinationIsSingleton?
    @signaling    = bundle.isVaccination? || bundle.isSubscriptionBundle?
    if ccn_blk = bundle.findBlock(CCNBlock)
      @signaling = (ccn_blk.method != :publish)
      #puts "Signaling #{ccn_blk.method} #{bundle.inspect}" if @signaling
    end

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

  def delays(regs = nil, considerReg = false)
    regs = [Struct::Registration.new(@dest, 0)] if regs.nil? or regs.empty?
    ret = regs.map do |reg|
      if delivered?(reg)
	start=considerReg ? [@created.to_i,reg.startTime.to_i].max : @created.to_i
	# If the bundle arrived at the node before it registered (can happen due
	# to flooding), the delay is considered to be 0 not a negative number.
	[0, @incidents[reg.node].min - start].max
      end
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

  def marshal_dump
    [@bundleId, @dest, @src, @payload_size, @created, @lifetime, @multicast,
      @transmissions, Hash.new.merge(@incidents), @signaling]
  end

  def marshal_load(lst)
    @bundleId, @dest, @src, @payload_size, @created, @lifetime, @multicast,
      @transmissions, @incidents, @signaling = lst
  end

  def to_yaml_properties
    @incidents = Hash.new.merge(@incidents) if @incidents
    %w{@bundleId @dest @src @payload_size @created @lifetime @multicast
    @transmissions @incidents @signaling}
  end

end

class SubscriptionSet

  class Subscription
    attr_accessor :node, :created, :expires, :delay, :hopCount

    def initialize(node, options)
      @node     = node
      @created  = options[:created] || RdtnTime.now
      @expires  = options[:expires]# || RdtnTime.now + 86400
      @delay    = options[:delay]   || (RdtnTime.now.to_i - @created.to_i)
      @hopCount = options[:hopCount].to_i
    end

  end

  attr_reader   :channels
  attr_accessor :subsRange, :defaultExpiry, :node

  def initialize(config, evDis, subsRange = 1, defaultExpiry = 3600*6)
    @node      = config.localEid
    @channels  = {}
    @subsRange = subsRange
    @defaultExpiry = defaultExpiry
  end

  def subscribe(uri, node = @node, options = {})
    subs = Subscription.new(node, options)
    subs.expires ||= RdtnTime.now + @defaultExpiry unless node == @node
    if channel!(uri).include? node
      s0 = channel!(uri)[node]
      s0.hopCount = [subs.hopCount, s0.hopCount].min
      s0.delay    = [subs.delay,    s0.delay   ].min
      s0.expires  = [subs.expires,  s0.expires ].max unless node == @node
    else
      channel!(uri)[node] = subs
    end
  end

  def unsubscribe(uri, node = @node)
    channel!(uri).delete node
    @channels.delete(uri) if @channels[uri].empty?
  end

  def subscribed?(uri)
    @channels.include? uri
  end

  def subscribers(uri)
    channel!(uri).keys
  end

  def delays(uri)
    ret = {}
    channel!(uri).each {|node, sub| ret[node] = sub.delay}
    ret
  end

  def hopCounts(uri)
    ret = {}
    channel!(uri).each {|node, sub| ret[node] = sub.hopCount}
    ret
  end

  def housekeeping!
    @channels.delete_if do |channel, subscribers|
      subscribers.delete_if {|node, sub| sub.expires && sub.expires.to_i <= RdtnTime.now.to_i}
      subscribers.empty?
    end
  end

  def import(subSet)
    subSet.channels.each do |channel, subscribers|
      subscribers.each do |node, sub|
	if sub.hopCount < @subsRange
	  subscribe(channel, node, :created  => sub.created,
		                   :expires  => sub.expires,
		                   :hopCount => sub.hopCount + 1)
	end
      end
    end
  end

  private

  def channel!(uri)
    channels[uri] = {} unless @channels.include? uri
    channels[uri]
  end


end

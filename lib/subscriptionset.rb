class SubscriptionSet

  class Subscription
    attr_accessor :uri, :node, :created, :expires, :delay, :hopCount, :delivered_revs

    def initialize(uri, node, options)
      @uri      = uri
      @node     = node
      @created  = options[:created] || RdtnTime.now
      @expires  = options[:expires]# || RdtnTime.now + 86400
      @delay    = options[:delay]   || (RdtnTime.now.to_i - @created.to_i)
      @hopCount = options[:hopCount].to_i
      @delivered_revs = []
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
    subs = Subscription.new(uri, node, options)
    subs.expires ||= RdtnTime.now + @defaultExpiry unless node == @node
    addSubscription(subs)
  end

  def addSubscription(subs)
    if channel!(subs.uri).include? subs.node
      s0 = channel!(subs.uri)[subs.node]
      s0.hopCount = [subs.hopCount, s0.hopCount].min
      s0.delay    = [subs.delay,    s0.delay   ].min
      s0.expires  = [subs.expires,  s0.expires ].max unless subs.node == @node
    else
      channel!(subs.uri)[subs.node] = subs
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

  def subscriptions(node)
    @channels.find_all{|uri, nodes| nodes.key? node}.map(&:first)
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

  def deliveredRevision(node, uri, rev)
    if @channels.key?(uri) && @channels[uri].key?(node)
      @channels[uri][node].delivered_revs << rev
    end
  end

  def hasRevision?(node, uri, rev)
    if @channels.key?(uri) && @channels[uri].key?(node)
      del_revs = channels[uri][node].delivered_revs
      del_revs.max >= rev unless del_revs.empty?
    end
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

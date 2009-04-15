require 'router'
require 'bundle'
require 'rdtntime'
require 'copycountblock'

class SprayWaitRouter < Router

  def initialize(config, evDis, options = {})
    super
    @init_cc = options[:initial_copycount] || 10
    @contMgr     = @config.contactManager
    
    @evToForward = @evDis.subscribe(:bundleToForward) do |b|
      @contMgr.links.each {|l| spray(b, l) if !l.is_a?(AppIF::AppProxy)}
    end
    @evAvailable = @evDis.subscribe(:routeAvailable) do |rentry|
      if store = @config.store and !rentry.link.is_a?(AppIF::AppProxy)
        store.each {|b| spray(b, rentry.link)}
      end
    end

  end

  def stop
    super
    @evDis.unsubscribe(:routeAvailable,  @evAvailable)
    @evDis.unsubscribe(:bundleToForward, @evToForward)
  end

  def spray(b, l)
    cc_block = b.findBlock(CopyCountBlock)
    unless cc_block
      cc_block = CopyCountBlock.new(b, @init_cc)
      b.addBlock cc_block
    end
    singleDest = b.destinationIsSingleton? ? b.destEid : nil
    l.remoteEids.each do |eid|
      if (cc_block.copycount > 1 or eid == b.destEid) and @config.forwardLog[b.bundleId].shouldAct?(:replicate, eid, l, singleDest)
        copy, _ = cc_block.bisect!
        # FIXME: Alert the storage that the bundle has changed
        enqueue(copy, l, :replicate)
      end
    end
  end

end

regRouter(:spraywait, SprayWaitRouter)
